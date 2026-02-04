#pragma once

#include <functional>
#include <sol/sol.hpp>
#include <cstdint>

// Central callback registry for Lua. Callbacks are always invoked on the main
// thread via lua_callbacks_dispatch; producers may enqueue work from any
// thread.

void lua_bind_callbacks(sol::state& lua, sol::table& lua_space);
uint64_t lua_callbacks_register(sol::function fn);
bool lua_callbacks_unregister(uint64_t id);
void lua_callbacks_enqueue(uint64_t id, std::function<sol::object(sol::state_view)> payload_builder);
void lua_callbacks_dispatch(sol::state_view lua, std::size_t max_results = 0);
void lua_callbacks_shutdown();

template <typename T>
inline void lua_callbacks_enqueue_value(uint64_t id, T value)
{
    lua_callbacks_enqueue(id, [value](sol::state_view lua) {
        return sol::make_object(lua, value);
    });
}
