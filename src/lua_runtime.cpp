#include "lua_runtime.h"

#include <cstdlib>
#include <iostream>

#include "asset_manager.h"
#include "lua_callbacks.h"
#include "lua_engine.h"
#include "lua_ray_box.h"
#include "lua_notify.h"
#include "lua_tray.h"
#include "lua_webbrowser.h"
#if defined(SPACE_ENABLE_WALLET_CORE)
#include "lua_wallet_core.h"
#endif

extern "C" int luaopen_lsqlite3(lua_State* L);

void lua_bind_opengl(sol::state&);
void lua_bind_image_io(sol::state&);
void lua_bind_json(sol::state&);
void lua_bind_toml(sol::state&);
void lua_bind_shaders(sol::state&);
void lua_bind_textures(sol::state&);
void lua_bind_glm(sol::state&);
void lua_bind_vector_buffer(sol::state&);
void lua_bind_graph_edge_batch(sol::state&);
void lua_bind_tree_sitter(sol::state&);
void lua_bind_msdf_atlas_gen(sol::state&);
void lua_bind_cgltf(sol::state&);
void lua_bind_fs(sol::state&);
void lua_bind_appdirs(sol::state&);
void lua_bind_random(sol::state&);
void lua_bind_physics(sol::state&);
void lua_bind_force_layout(sol::state&);
void lua_bind_colors(sol::state&);
void lua_bind_audio(sol::state&);
void lua_bind_audio_input(sol::state&);
void lua_bind_aubio(sol::state&);
#if defined(SPACE_HAS_VTERM)
void lua_bind_terminal(sol::state&);
#endif
void lua_bind_input_state(sol::state&);
void lua_bind_zmq(sol::state&);
void lua_bind_matrix(sol::state&);
void lua_bind_logging(sol::state&);
void lua_bind_uuid(sol::state&);
void lua_bind_shell(sol::state&);
void lua_bind_process(sol::state&);
#if defined(SPACE_ENABLE_WALLET_CORE)
void lua_bind_wallet_core(sol::state&);
#endif
LuaRuntime::LuaRuntime() = default;

void LuaRuntime::init()
{
    install_fatal_traceback();
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::table,
                       sol::lib::math, sol::lib::string, sol::lib::debug,
                       sol::lib::io, sol::lib::os, sol::lib::utf8);
    lua.require("lsqlite3", luaopen_lsqlite3);
    install_base_bindings();
    configure_package_paths();
    lua["package"]["preload"]["runtime"] = [this](sol::this_state ts) -> sol::object {
        sol::state_view lua_view(ts);
        sol::table runtime_table = lua_view.create_table();
        runtime_table["assets-path"] = assets_path_value;
        runtime_table["fennel-path"] = fennel_path_value;
        return sol::make_object(lua_view, runtime_table);
    };

}

void LuaRuntime::install_fennel(bool correlate)
{
    std::string correlate_flag = correlate ? "true" : "false";
    std::string script =
        "app = app or {}\n"
        "local fennel = require(\"fennel\")\n"
        "fennel.path = \"" + fennel_path_value + "\" .. \";\" .. fennel.path\n"
        "fennel.install({ correlate = " + correlate_flag + " })\n";
    lua.script(script);
}

void LuaRuntime::require_module(const std::string& name)
{
    lua.script("require(\"" + name + "\")");
}

void LuaRuntime::install_fatal_traceback()
{
    lua["__FENNEL_FATAL_TRACEBACK"] =
        [](sol::object err, sol::this_state ts) -> sol::object {

            sol::state_view lua(ts);

            std::string errstr = err.as<std::string>();

            sol::function tb = lua["debug"]["traceback"];
            std::string traced = tb(errstr, 2);

            std::cerr << traced << "\n";

            std::abort();

            return sol::make_object(lua, traced);
        };
}

void LuaRuntime::install_base_bindings()
{
    {
        sol::table callbacks_space = lua.create_table();
        lua_bind_callbacks(lua, callbacks_space);
    }
    lua_bind_opengl(lua);
    lua_bind_image_io(lua);
    lua_bind_json(lua);
    lua_bind_toml(lua);
    lua_bind_shaders(lua);
    lua_bind_textures(lua);
    lua_bind_glm(lua);
    lua_bind_vector_buffer(lua);
    lua_bind_graph_edge_batch(lua);
    lua_bind_tree_sitter(lua);
    lua_bind_msdf_atlas_gen(lua);
    lua_bind_cgltf(lua);
    lua_bind_fs(lua);
    lua_bind_appdirs(lua);
    lua_bind_random(lua);
    lua_bind_physics(lua);
    lua_bind_force_layout(lua);
    lua_bind_colors(lua);
    lua_bind_audio(lua);
    lua_bind_audio_input(lua);
    lua_bind_aubio(lua);
#if defined(SPACE_HAS_VTERM)
    lua_bind_terminal(lua);
#endif
    lua_bind_input_state(lua);
    lua_bind_zmq(lua);
    lua_bind_matrix(lua);
    lua_bind_logging(lua);
    lua_bind_uuid(lua);
    lua_bind_shell(lua);
    lua_bind_process(lua);
#if defined(SPACE_ENABLE_WALLET_CORE)
    lua_bind_wallet_core(lua);
#else
    {
        sol::table package = lua["package"];
        sol::table preload = package["preload"];
        preload.set_function("wallet-core", [](sol::this_state state) {
            sol::state_view lua_state(state);
            sol::table wallet_core = lua_state.create_table();
            wallet_core["available"] = false;
            wallet_core["missing-reason"] = "wallet-core built without support";
            sol::table mt = lua_state.create_table();
            mt["__index"] = [](sol::this_state, sol::object key) -> sol::object {
                std::string key_name = "<non-string>";
                if (key.is<std::string>()) {
                    key_name = key.as<std::string>();
                }
                throw sol::error("wallet-core unavailable (built without wallet-core support): " + key_name);
                return sol::nil;
            };
            wallet_core[sol::metatable_key] = mt;
            return wallet_core;
        });
    }
#endif
    lua_bind_engine(lua);
    lua_bind_ray_box(lua);
    lua_bind_tray(lua);
    lua_bind_notify(lua);
    lua_bind_webbrowser(lua);
}

void LuaRuntime::configure_package_paths()
{
    assets_path_value = AssetManager::getAssetPath("");
    std::string lua_path = AssetManager::getAssetPath("lua");
    std::string package_path = lua_path + "/?.lua";
    fennel_path_value = lua_path + "/?.fnl";
    lua["package"]["path"] = lua["package"]["path"].get<std::string>() + ";" + package_path;
}
