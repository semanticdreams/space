#include <sol/sol.hpp>
#include "shader.h"
#include "resource_manager.h"

Shader lua_load_shader(const std::string& name, const std::string& vertexCode, const std::string& fragmentCode,
                       sol::optional<std::string> geometryCode) {
    return ResourceManager::loadShader(name, vertexCode, fragmentCode, geometryCode.value_or(""));
}

Shader lua_load_shader_from_files(const std::string& name, const std::string& vertexPath, const std::string& fragmentPath,
                                  sol::optional<std::string> geometryPath) {
    return ResourceManager::loadShaderFromFile(name, vertexPath, fragmentPath, geometryPath.value_or(""));
}

Shader lua_get_shader(const std::string& name) {
    return ResourceManager::getShader(name);
}

namespace {

sol::table create_shaders_table(sol::state_view lua)
{
    // Bind the Shader class
    sol::table shaders_table = lua.create_table();
    shaders_table.new_usertype<Shader>("Shader",
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

    shaders_table.set_function("load-shader", &lua_load_shader);
    shaders_table.set_function("load-shader-from-files", &lua_load_shader_from_files);
    shaders_table.set_function("get-shader", &lua_get_shader);
    return shaders_table;
}

} // namespace

void lua_bind_shaders(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("shaders", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_shaders_table(lua);
    });
}
