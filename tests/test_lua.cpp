#include <sol/sol.hpp>
#include <iostream>
#include "engine.h"
#include "asset_manager.h"
#include "appdirs.h"
#include "paths.h"

LogConfig LOG_CONFIG = {};

extern "C" int luaopen_lsqlite3(lua_State* L);

void lua_bind_bullet(sol::state&);
void lua_bind_opengl(sol::state&);
void lua_bind_json(sol::state&);
void lua_bind_shaders(sol::state&);
void lua_bind_glm(sol::state&);
void lua_bind_vector_buffer(sol::state&);
void lua_bind_tree_sitter(sol::state&);

int main() {
    LOG_CONFIG.reporting_level = Debug;
    LOG_CONFIG.restart = true;
    if (LOG_CONFIG.restart)
    {
        Log::restart();
    }

    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::table, sol::lib::math, sol::lib::string, sol::lib::debug, sol::lib::io, sol::lib::os);
    lua.require("lsqlite3", luaopen_lsqlite3);
    lua_bind_opengl(lua);
    lua_bind_bullet(lua);
    lua_bind_json(lua);
    lua_bind_shaders(lua);
    lua_bind_glm(lua);
    lua_bind_vector_buffer(lua);
    lua_bind_tree_sitter(lua);
    std::string luaPath = AssetManager::getAssetPath("lua");
    std::cout << "luaPath is " << luaPath << std::endl;
    std::string packagePath = luaPath + "/?.lua";
    std::string fennelPath = luaPath + "/?.fnl";
    lua["package"]["path"] = lua["package"]["path"].get<std::string>() + ";" + packagePath;
    auto lua_space = lua.create_named_table("space");
    lua_space["data_dir"] = get_user_data_dir("space");
    lua_space.set_function("join_path", join_path);

    lua.script(R"(
    local fennel = require("fennel")
    fennel.path = ")" + fennelPath + R"(" .. ";" .. fennel.path
    fennel.install()
    require("main")
    )");

    try {
        lua.script(R"(
        require("test")
        )");
    } catch (const sol::error& e) {
        std::cerr << "Lua error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
