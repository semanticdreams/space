#include <sol/sol.hpp>

#include <string>

#include "appdirs.h"

namespace {

std::string resolve_app_name(sol::optional<std::string> app_name)
{
    return app_name.value_or("space");
}

sol::table create_appdirs_table(sol::state_view lua)
{
    sol::table appdirs = lua.create_table();

    appdirs.set_function("user-data-dir", [](sol::optional<std::string> app_name) {
        return get_user_data_dir(resolve_app_name(app_name));
    });

    appdirs.set_function("user-config-dir", [](sol::optional<std::string> app_name) {
        return get_user_config_dir(resolve_app_name(app_name));
    });

    appdirs.set_function("user-cache-dir", [](sol::optional<std::string> app_name) {
        return get_user_cache_dir(resolve_app_name(app_name));
    });

    appdirs.set_function("user-log-dir", [](sol::optional<std::string> app_name) {
        return get_user_log_dir(resolve_app_name(app_name));
    });

    appdirs.set_function("home-dir", &get_home_dir);
    appdirs.set_function("tmp-dir", &get_tmp_dir);
    appdirs.set_function("site-data-dir", [](sol::optional<std::string> app_name) {
        return get_site_data_dir(resolve_app_name(app_name));
    });
    appdirs.set_function("site-config-dir", [](sol::optional<std::string> app_name) {
        return get_site_config_dir(resolve_app_name(app_name));
    });

    return appdirs;
}

} // namespace

void lua_bind_appdirs(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("appdirs", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_appdirs_table(lua);
    });
}
