#include "lua_shell.h"

#include <string>

namespace {

[[noreturn]] void shell_unsupported(const char* name)
{
    throw sol::error(std::string("shell.") + name + " is not supported on Windows builds");
}

} // namespace

void lua_bind_shell(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("shell", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table shell_table = lua_view.create_table();
        shell_table.set_function("bash", [](sol::variadic_args) {
            shell_unsupported("bash");
        });
        return shell_table;
    });
}
