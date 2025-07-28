#include <sol/sol.hpp>
#include "shader.h"
#include "resource_manager.h"

Shader lua_load_shader(const std::string& name, const std::string& vertexCode, const std::string& fragmentCode, const std::string& geometryCode = "") {
    return ResourceManager::loadShader(name, vertexCode, fragmentCode, geometryCode);
}

Shader lua_get_shader(const std::string& name) {
    return ResourceManager::getShader(name);
}

void lua_bind_shaders(sol::state& lua) {
    // Bind the Shader class
    lua.new_usertype<Shader>("Shader",
        "use", &Shader::use
    );

    // Create the shaders table and expose functions
    sol::table shaders_table = lua.create_table();
    shaders_table.set_function("load_shader", &lua_load_shader);
    shaders_table.set_function("get_shader", &lua_get_shader);

    lua["shaders"] = shaders_table;
}
