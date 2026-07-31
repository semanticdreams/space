#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

#include "space_log_path.h"

namespace fs = std::filesystem;

namespace {

bool set_env_var(const std::string& key, const std::string& value)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), value.c_str()) == 0;
#else
    return setenv(key.c_str(), value.c_str(), 1) == 0;
#endif
}

bool unset_env_var(const std::string& key)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), "") == 0;
#else
    return unsetenv(key.c_str()) == 0;
#endif
}

class ScopedEnv {
public:
    ScopedEnv(std::string key, std::optional<std::string> value) : key_(std::move(key))
    {
        const char* existing = std::getenv(key_.c_str());
        if (existing) {
            old_ = std::string(existing);
        }
        ok_ = value ? set_env_var(key_, *value) : unset_env_var(key_);
    }

    ~ScopedEnv()
    {
        if (old_) {
            set_env_var(key_, *old_);
        } else {
            unset_env_var(key_);
        }
    }

    bool ok() const { return ok_; }

private:
    std::string key_;
    std::optional<std::string> old_;
    bool ok_ = false;
};

fs::path make_temp_root(const std::string& name)
{
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / (name + "_" + std::to_string(stamp));
    fs::create_directories(root);
    return root;
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

bool test_space_log_dir_override()
{
    fs::path root = make_temp_root("space_log_override");
    ScopedEnv logDir("SPACE_LOG_DIR", (root / "logs").string());
    ScopedEnv xdg("XDG_CACHE_HOME", (root / "cache").string());
    return check(space_log::resolve_log_path() == root / "logs" / "space.log",
                 "SPACE_LOG_DIR should select <dir>/space.log");
}

bool test_empty_space_log_dir_uses_default()
{
    fs::path root = make_temp_root("space_log_empty_override");
    ScopedEnv logDir("SPACE_LOG_DIR", std::string(""));
    ScopedEnv xdg("XDG_CACHE_HOME", (root / "cache").string());
    return check(space_log::resolve_log_path() == root / "cache" / "space" / "log" / "space.log",
                 "empty SPACE_LOG_DIR should use appdirs default");
}

bool test_default_uses_user_log_dir()
{
    fs::path root = make_temp_root("space_log_default");
    ScopedEnv logDir("SPACE_LOG_DIR", std::nullopt);
    ScopedEnv xdg("XDG_CACHE_HOME", (root / "cache").string());
    return check(space_log::resolve_log_path() == root / "cache" / "space" / "log" / "space.log",
                 "default should use XDG cache app log dir on Linux-style appdirs");
}

bool test_ensure_log_directory_creates_parent()
{
    fs::path root = make_temp_root("space_log_create");
    fs::path path = root / "new" / "logs" / "space.log";
    space_log::ensure_log_directory(path);
    return check(fs::is_directory(path.parent_path()), "ensure_log_directory should create parent dirs");
}

bool test_ensure_log_directory_rejects_file_parent()
{
    fs::path root = make_temp_root("space_log_invalid");
    fs::path fileParent = root / "not-a-dir";
    std::ofstream out(fileParent);
    out << "not a directory\n";
    out.close();

    try {
        space_log::ensure_log_directory(fileParent / "space.log");
    } catch (const std::runtime_error& e) {
        std::string message = e.what();
        return check(message.find("not a directory") != std::string::npos ||
                         message.find(fileParent.string()) != std::string::npos,
                     "invalid parent error should mention the parent path");
    }

    std::cerr << "FAIL: ensure_log_directory should throw for file parent\n";
    return false;
}

} // namespace

int main()
{
    bool ok = true;
    ok = test_space_log_dir_override() && ok;
    ok = test_empty_space_log_dir_uses_default() && ok;
    ok = test_default_uses_user_log_dir() && ok;
    ok = test_ensure_log_directory_creates_parent() && ok;
    ok = test_ensure_log_directory_rejects_file_parent() && ok;
    return ok ? 0 : 1;
}
