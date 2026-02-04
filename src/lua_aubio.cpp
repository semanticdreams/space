#include "lua_aubio_bindings.h"

namespace lua_aubio {

static sol::table create_aubio_vec_table(sol::state_view lua)
{
    sol::table aubio_table = lua.create_table();
    register_vec(lua, aubio_table);
    return aubio_table;
}

static sol::table create_aubio_spectral_table(sol::state_view lua)
{
    sol::table aubio_table = lua.create_table();
    register_spectral(lua, aubio_table);
    return aubio_table;
}

static sol::table create_aubio_temporal_table(sol::state_view lua)
{
    sol::table aubio_table = lua.create_table();
    register_temporal(lua, aubio_table);
    return aubio_table;
}

static sol::table create_aubio_io_table(sol::state_view lua)
{
    sol::table aubio_table = lua.create_table();
    register_io(lua, aubio_table);
    return aubio_table;
}

static sol::table create_aubio_synth_table(sol::state_view lua)
{
    sol::table aubio_table = lua.create_table();
    register_synth(lua, aubio_table);
    return aubio_table;
}

static sol::table create_aubio_utils_table(sol::state_view lua)
{
    sol::table aubio_table = lua.create_table();
    register_utils(lua, aubio_table);
    return aubio_table;
}
} // namespace lua_aubio

void lua_bind_aubio(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("aubio/vec", [](sol::this_state state) {
        sol::state_view lua(state);
        return lua_aubio::create_aubio_vec_table(lua);
    });
    preload.set_function("aubio/spectral", [](sol::this_state state) {
        sol::state_view lua(state);
        return lua_aubio::create_aubio_spectral_table(lua);
    });
    preload.set_function("aubio/temporal", [](sol::this_state state) {
        sol::state_view lua(state);
        return lua_aubio::create_aubio_temporal_table(lua);
    });
    preload.set_function("aubio/io", [](sol::this_state state) {
        sol::state_view lua(state);
        return lua_aubio::create_aubio_io_table(lua);
    });
    preload.set_function("aubio/synth", [](sol::this_state state) {
        sol::state_view lua(state);
        return lua_aubio::create_aubio_synth_table(lua);
    });
    preload.set_function("aubio/utils", [](sol::this_state state) {
        sol::state_view lua(state);
        return lua_aubio::create_aubio_utils_table(lua);
    });
}
