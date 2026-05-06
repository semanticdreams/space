#include <sol/sol.hpp>

#include <efsw/efsw.hpp>

#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

std::string normalize_path(const fs::path& path)
{
    return path.lexically_normal().string();
}

std::string action_name(efsw::Action action)
{
    switch (action) {
    case efsw::Actions::Add:
        return "add";
    case efsw::Actions::Delete:
        return "delete";
    case efsw::Actions::Modified:
        return "modified";
    case efsw::Actions::Moved:
        return "moved";
    default:
        return "unknown";
    }
}

struct WatchEvent {
    efsw::WatchID watch_id { 0 };
    std::string directory {};
    std::string filename {};
    std::string path {};
    std::string action {};
    std::string old_filename {};
    std::optional<std::string> old_path {};
    bool missed { false };
};

class LuaFileWatcher final : public efsw::FileWatchListener {
public:
    explicit LuaFileWatcher(bool generic)
        : watcher(std::make_unique<efsw::FileWatcher>(generic))
    {
    }

    LuaFileWatcher(const LuaFileWatcher&) = delete;
    LuaFileWatcher& operator=(const LuaFileWatcher&) = delete;

    ~LuaFileWatcher() override
    {
        drop();
    }

    efsw::WatchID add_watch(const std::string& directory, bool recursive)
    {
        assert_not_dropped("add-watch");
        if (directory.empty()) {
            throw sol::error("file-watch add-watch requires non-empty directory");
        }
        const efsw::WatchID watch_id = watcher->addWatch(directory, this, recursive);
        if (watch_id < 0) {
            throw sol::error("file-watch add-watch failed for " + directory + ": "
                             + efsw::Errors::Log::getLastErrorLog());
        }
        watched_directories[watch_id] = directory;
        return watch_id;
    }

    void remove_watch(efsw::WatchID watch_id)
    {
        assert_not_dropped("remove-watch");
        watcher->removeWatch(watch_id);
        watched_directories.erase(watch_id);
    }

    void start()
    {
        assert_not_dropped("start");
        if (started) {
            return;
        }
        watcher->watch();
        started = true;
    }

    void follow_symlinks(bool follow)
    {
        assert_not_dropped("follow-symlinks");
        watcher->followSymlinks(follow);
    }

    void allow_out_of_scope_links(bool allow)
    {
        assert_not_dropped("allow-out-of-scope-links");
        watcher->allowOutOfScopeLinks(allow);
    }

    bool follow_symlinks_enabled() const
    {
        return watcher && watcher->followSymlinks();
    }

    bool out_of_scope_links_allowed() const
    {
        return watcher && watcher->allowOutOfScopeLinks();
    }

    sol::table poll(sol::this_state ts)
    {
        assert_not_dropped("poll");
        sol::state_view lua(ts);
        std::vector<WatchEvent> drained;
        {
            std::lock_guard<std::mutex> lock(events_mutex);
            drained.swap(events);
        }

        sol::table result = lua.create_table();
        std::size_t index = 1;
        for (const WatchEvent& event : drained) {
            sol::table entry = lua.create_table();
            entry["watch-id"] = event.watch_id;
            entry["dir"] = event.directory;
            entry["filename"] = event.filename;
            entry["path"] = event.path;
            entry["action"] = event.action;
            entry["missed"] = event.missed;
            if (event.old_filename.empty()) {
                entry["old-filename"] = sol::lua_nil;
            } else {
                entry["old-filename"] = event.old_filename;
            }
            if (event.old_path.has_value()) {
                entry["old-path"] = event.old_path.value();
            } else {
                entry["old-path"] = sol::lua_nil;
            }
            result[index++] = entry;
        }
        return result;
    }

    sol::table directories(sol::this_state ts)
    {
        assert_not_dropped("directories");
        sol::state_view lua(ts);
        sol::table result = lua.create_table();
        std::vector<std::string> watched = watcher->directories();
        std::size_t index = 1;
        for (const std::string& directory : watched) {
            result[index++] = directory;
        }
        return result;
    }

    bool started_watching() const
    {
        return started;
    }

    void drop()
    {
        if (dropped) {
            return;
        }
        dropped = true;
        watched_directories.clear();
        watcher.reset();
        std::lock_guard<std::mutex> lock(events_mutex);
        events.clear();
    }

    void handleFileAction(efsw::WatchID watchid, const std::string& dir, const std::string& filename,
        efsw::Action action, std::string old_filename) override
    {
        WatchEvent event;
        event.watch_id = watchid;
        event.directory = dir;
        event.filename = filename;
        event.path = normalize_path(fs::path(dir) / filename);
        event.action = action_name(action);
        event.old_filename = std::move(old_filename);
        if (!event.old_filename.empty()) {
            event.old_path = normalize_path(fs::path(dir) / event.old_filename);
        }

        std::lock_guard<std::mutex> lock(events_mutex);
        events.push_back(std::move(event));
    }

    void handleMissedFileActions(efsw::WatchID watchid, const std::string& dir) override
    {
        WatchEvent event;
        event.watch_id = watchid;
        event.directory = dir;
        event.action = "missed";
        event.missed = true;

        std::lock_guard<std::mutex> lock(events_mutex);
        events.push_back(std::move(event));
    }

private:
    void assert_not_dropped(const char* context) const
    {
        if (dropped || !watcher) {
            throw sol::error(std::string("file-watch ") + context + " called after drop");
        }
    }

    std::unique_ptr<efsw::FileWatcher> watcher;
    std::unordered_map<efsw::WatchID, std::string> watched_directories {};
    std::mutex events_mutex {};
    std::vector<WatchEvent> events {};
    bool started { false };
    bool dropped { false };
};

std::shared_ptr<LuaFileWatcher> create_file_watcher(sol::table options)
{
    const bool generic = options.get_or("generic", false) || options.get_or("generic?", false);
    std::shared_ptr<LuaFileWatcher> watcher = std::make_shared<LuaFileWatcher>(generic);
    watcher->follow_symlinks(options.get_or("follow-symlinks", false) || options.get_or("follow-symlinks?", false));
    watcher->allow_out_of_scope_links(options.get_or("allow-out-of-scope-links", false)
                                      || options.get_or("allow-out-of-scope-links?", false));
    return watcher;
}

sol::table create_module(sol::this_state ts)
{
    sol::state_view lua(ts);
    sol::table module = lua.create_table();
    module.set_function("FileWatcher", [](sol::this_state state, sol::optional<sol::table> options) {
        sol::state_view lua(state);
        return create_file_watcher(options.value_or(lua.create_table()));
    });
    module.set_function("last-error", []() -> std::string {
        return efsw::Errors::Log::getLastErrorLog();
    });
    module["actions"] = lua.create_table_with(
        "add", "add",
        "delete", "delete",
        "modified", "modified",
        "moved", "moved",
        "missed", "missed");
    return module;
}

} // namespace

void lua_bind_file_watch(sol::state& lua)
{
    lua.new_usertype<LuaFileWatcher>("SpaceFileWatcher", sol::no_constructor,
        "add-watch", [](LuaFileWatcher& self, const std::string& directory, sol::optional<bool> recursive) {
            return self.add_watch(directory, recursive.value_or(true));
        },
        "remove-watch", &LuaFileWatcher::remove_watch,
        "start", &LuaFileWatcher::start,
        "poll", &LuaFileWatcher::poll,
        "directories", &LuaFileWatcher::directories,
        "follow-symlinks", &LuaFileWatcher::follow_symlinks,
        "allow-out-of-scope-links", &LuaFileWatcher::allow_out_of_scope_links,
        "follow-symlinks-enabled?", &LuaFileWatcher::follow_symlinks_enabled,
        "allow-out-of-scope-links?", &LuaFileWatcher::out_of_scope_links_allowed,
        "started?", &LuaFileWatcher::started_watching,
        "drop", &LuaFileWatcher::drop);

    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("file-watch", [](sol::this_state state) {
        return create_module(state);
    });
}
