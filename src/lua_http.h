#pragma once

#include <sol/sol.hpp>

#include "http_client.h"

void lua_bind_http(sol::state& lua, HttpClient& client);
void lua_http_drop(sol::state& lua);
void lua_http_dispatch(sol::state& lua);
