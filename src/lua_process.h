#pragma once

#include <sol/sol.hpp>

void lua_bind_process(sol::state& lua);
void lua_process_dispatch(sol::state& lua);
void lua_process_drop(sol::state& lua);
