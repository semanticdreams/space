#include <string>

#include "lua_webbrowser.h"
#include "webbrowser.hpp"

namespace {

webbrowser::open_mode parse_mode(const sol::optional<std::string>& mode_opt)
{
    if (!mode_opt) {
        return webbrowser::same_window;
    }
    const std::string& mode_str = mode_opt.value();
    if (mode_str == "new-window" || mode_str == "window") {
        return webbrowser::new_window;
    }
    if (mode_str == "new-tab" || mode_str == "tab") {
        return webbrowser::new_tab;
    }
    if (mode_str == "same-window" || mode_str == "same") {
        return webbrowser::same_window;
    }
    throw sol::error("webbrowser.open invalid mode: " + mode_str);
}

bool open_target(const std::string& target,
                 const sol::optional<std::string>& mode_opt,
                 const sol::optional<bool>& autoraise_opt)
{
    if (target.empty()) {
        throw sol::error("webbrowser.open requires a non-empty target");
    }
    webbrowser::open_mode mode = parse_mode(mode_opt);
    bool autoraise = autoraise_opt.value_or(true);
    return webbrowser::open(target, mode, autoraise);
}

bool open_new(const std::string& target)
{
    if (target.empty()) {
        throw sol::error("webbrowser.open_new requires a non-empty target");
    }
    return webbrowser::open_new(target);
}

bool open_new_tab(const std::string& target)
{
    if (target.empty()) {
        throw sol::error("webbrowser.open_new_tab requires a non-empty target");
    }
    return webbrowser::open_new_tab(target);
}

} // namespace

namespace {

sol::table create_webbrowser_table(sol::state_view lua)
{
    sol::table module = lua.create_table();
    module.set_function("open", open_target);
    module.set_function("open_new", open_new);
    module.set_function("open_new_tab", open_new_tab);
    return module;
}

} // namespace

void lua_bind_webbrowser(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("webbrowser", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_webbrowser_table(lua);
    });
}
