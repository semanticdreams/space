#include <deque>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "lua_tray.h"
#include "tray.h"

namespace {

struct CallbackRef {
    sol::function fn;
};

struct MenuStorage {
    std::vector<tray_menu> items;
    std::vector<std::unique_ptr<MenuStorage>> children;
};

struct TrayHandle {
    tray native{};
    std::string icon_storage{};
    MenuStorage menu_storage{};
    std::deque<std::string> text_storage{};
    std::vector<std::unique_ptr<CallbackRef>> callbacks{};
    bool running{false};
    std::string last_error{};

    TrayHandle() = default;
    explicit TrayHandle(const sol::table& spec) {
        if (!rebuild_from_spec(spec)) {
            sol::error err(last_error);
            throw err;
        }
    }
    TrayHandle(const TrayHandle&) = delete;
    TrayHandle& operator=(const TrayHandle&) = delete;
    TrayHandle(TrayHandle&&) noexcept = default;
    TrayHandle& operator=(TrayHandle&&) noexcept = default;

    bool rebuild_from_spec(const sol::table& spec) {
        const sol::object icon_obj = spec["icon"];
        const sol::object menu_obj = spec["menu"];
        if (!icon_obj.is<std::string>()) {
            last_error = "tray spec missing string icon";
            return false;
        }
        if (!menu_obj.is<sol::table>()) {
            last_error = "tray spec missing menu table";
            return false;
        }

        icon_storage = icon_obj.as<std::string>();
        text_storage.clear();
        callbacks.clear();
        menu_storage = MenuStorage{};

        if (!build_menu(menu_obj.as<sol::table>(), menu_storage)) {
            return false;
        }

        native.icon = const_cast<char*>(icon_storage.c_str());
        native.menu = menu_storage.items.data();
        return true;
    }

    bool start() {
#if defined(TRAY_BACKEND_NONE)
        running = false;
        last_error = get_compile_reason();
        return false;
#else
        if (const char* runtime_reason = tray_runtime_reason()) {
            running = false;
            last_error = runtime_reason;
            return false;
        }
        const int res = tray_init(&native);
        if (res < 0) {
            running = false;
            last_error = "tray_init failed (missing runtime tray deps?)";
            return false;
        }
        running = true;
        return true;
#endif
    }

    void update(const sol::optional<sol::table>& spec) {
        if (spec) {
            if (!rebuild_from_spec(*spec)) {
                sol::error err(last_error);
                throw err;
            }
        }
        tray_update(&native);
    }

    int loop(bool blocking) {
        return tray_loop(blocking ? 1 : 0);
    }

    void exit() {
        if (running) {
            tray_exit();
            running = false;
        }
    }

    std::string get_compile_reason() const {
#ifdef TRAY_BACKEND_REASON
        return std::string{TRAY_BACKEND_REASON};
#else
        return "";
#endif
    }

    std::string backend_name() const {
#ifdef TRAY_BACKEND_NAME
        return std::string{TRAY_BACKEND_NAME};
#else
        return "unknown";
#endif
    }

    ~TrayHandle() {
        exit();
    }

private:
    static void menu_callback(tray_menu* item) {
        if (!item || !item->context) {
            return;
        }
        auto* cbref = reinterpret_cast<CallbackRef*>(item->context);
        if (cbref->fn.valid()) {
            cbref->fn(item->checked != 0);
        }
    }

    bool build_menu(const sol::table& items, MenuStorage& storage) {
        storage.items.clear();
        storage.children.clear();

        const auto len = items.size();
        storage.items.reserve(len + 1);
        for (std::size_t i = 1; i <= len; ++i) {
            sol::object obj = items[i];
            if (!obj.is<sol::table>()) {
                last_error = "menu item at index " + std::to_string(i) + " must be a table";
                return false;
            }
            sol::table entry = obj.as<sol::table>();
            tray_menu m{};

            const sol::object text_obj = entry["text"];
            if (text_obj.get_type() == sol::type::string) {
                text_storage.emplace_back(text_obj.as<std::string>());
                m.text = const_cast<char*>(text_storage.back().c_str());
            } else if (text_obj.valid()) {
                last_error = "menu item text must be a string or nil";
                return false;
            } else {
                last_error = "menu item missing text";
                return false;
            }

            m.disabled = entry.get_or("disabled", false) ? 1 : 0;
            const sol::optional<bool> checked_opt = entry["checked"];
            const bool checkable = entry.get_or("checkable", false) || checked_opt.has_value();
            m.checkable = checkable ? 1 : 0;
            m.checked = checked_opt.value_or(false) ? 1 : 0;

            const sol::object cb_obj = entry["cb"];
            if (cb_obj.is<sol::function>()) {
                auto ref = std::make_unique<CallbackRef>();
                ref->fn = cb_obj.as<sol::function>();
                m.cb = menu_callback;
                m.context = ref.get();
                callbacks.push_back(std::move(ref));
            } else {
                m.cb = nullptr;
                m.context = nullptr;
            }

            const sol::object submenu_obj = entry["submenu"];
            if (submenu_obj.is<sol::table>()) {
                auto child = std::make_unique<MenuStorage>();
                if (!build_menu(submenu_obj.as<sol::table>(), *child)) {
                    return false;
                }
                m.submenu = child->items.data();
                storage.children.push_back(std::move(child));
            } else if (submenu_obj.valid()) {
                last_error = "submenu must be a table";
                return false;
            } else {
                m.submenu = nullptr;
            }

            // Non-checkable items should not carry a checked state on backends
            // that infer checkboxes from presence; keep checked zeroed when
            // checkable is false.
            if (!m.checkable) {
                m.checked = 0;
            }

            storage.items.push_back(m);
        }

        storage.items.push_back(tray_menu{});
        return true;
    }
};

sol::table support_info(sol::state_view lua) {
    sol::table t = lua.create_table();
#if defined(TRAY_BACKEND_NONE)
    t["supported"] = false;
    t["backend"] = std::string{TRAY_BACKEND_NAME};
    t["reason"] = std::string{TRAY_BACKEND_REASON};
#else
    t["supported"] = true;
#ifdef TRAY_BACKEND_NAME
    t["backend"] = std::string{TRAY_BACKEND_NAME};
#else
    t["backend"] = "unknown";
#endif
    t["reason"] = "";
#endif
    return t;
}

}  // namespace

namespace {

sol::table create_tray_table(sol::state_view lua)
{
    sol::table tray = lua.create_table();
    tray.new_usertype<TrayHandle>("TrayHandle",
        sol::no_constructor,
        "start", &TrayHandle::start,
        "update", &TrayHandle::update,
        "loop", &TrayHandle::loop,
        "exit", &TrayHandle::exit,
        "last-error", [](TrayHandle& self) { return self.last_error; },
        "backend", [](TrayHandle& self) { return self.backend_name(); }
    );

    tray["supported"] = support_info(lua);
    tray["support"] = [](sol::this_state s) {
        return support_info(sol::state_view{s});
    };
    tray["create"] = [](const sol::table& spec) {
        return TrayHandle(spec);
    };
    return tray;
}

}  // namespace

void lua_bind_tray(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("tray", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_tray_table(lua);
    });
}
