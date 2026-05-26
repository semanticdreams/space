#pragma once

#include <sol/sol.hpp>

void lua_bind_http_server(sol::state& lua);
void lua_http_server_dispatch(sol::state_view lua);
void lua_http_server_shutdown_all();
