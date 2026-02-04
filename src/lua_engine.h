#pragma once

#include <sol/sol.hpp>

void lua_bind_engine(sol::state& lua);
bool lua_engine_has_active();
void lua_engine_shutdown_active();
