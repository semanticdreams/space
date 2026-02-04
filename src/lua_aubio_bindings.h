#ifndef SPACE_LUA_AUBIO_BINDINGS_H
#define SPACE_LUA_AUBIO_BINDINGS_H

#include <sol/sol.hpp>

namespace lua_aubio {

void register_vec(sol::state_view lua, sol::table& aubio_table);
void register_spectral(sol::state_view lua, sol::table& aubio_table);
void register_temporal(sol::state_view lua, sol::table& aubio_table);
void register_io(sol::state_view lua, sol::table& aubio_table);
void register_synth(sol::state_view lua, sol::table& aubio_table);
void register_utils(sol::state_view lua, sol::table& aubio_table);
void ensure_types_registered(sol::state_view lua);

} // namespace lua_aubio

void lua_bind_aubio(sol::state& lua);

#endif // SPACE_LUA_AUBIO_BINDINGS_H
