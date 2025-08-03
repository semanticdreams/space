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
        "id", &Shader::id,
        "use", &Shader::use,

        "setFloat", &Shader::setFloat,
        "setInteger", &Shader::setInteger,

        // Overloads for setVector2f
        "setVector2f", sol::overload(
            static_cast<void (Shader::*)(const GLchar*, GLfloat, GLfloat) const>(&Shader::setVector2f),
            static_cast<void (Shader::*)(const GLchar*, const glm::vec2&) const>(&Shader::setVector2f)
        ),

        // Overloads for setVector3f
        "setVector3f", sol::overload(
            static_cast<void (Shader::*)(const GLchar*, GLfloat, GLfloat, GLfloat) const>(&Shader::setVector3f),
            static_cast<void (Shader::*)(const GLchar*, const glm::vec3&) const>(&Shader::setVector3f)
        ),

        // Overloads for setVector4f
        "setVector4f", sol::overload(
            static_cast<void (Shader::*)(const GLchar*, GLfloat, GLfloat, GLfloat, GLfloat) const>(&Shader::setVector4f),
            static_cast<void (Shader::*)(const GLchar*, const glm::vec4&) const>(&Shader::setVector4f)
        ),

        "setMatrix4", &Shader::setMatrix4
    );

    // Create the shaders table and expose functions
    sol::table shaders_table = lua.create_table();
    shaders_table.set_function("load_shader", &lua_load_shader);
    shaders_table.set_function("get_shader", &lua_get_shader);

    lua["shaders"] = shaders_table;
}
