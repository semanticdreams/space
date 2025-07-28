#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>

void lua_bind_glm(sol::state& lua) {
    lua.new_usertype<glm::vec4>("vec4",
        sol::constructors<
            glm::vec4(),                         // default
            glm::vec4(float),                    // uniform fill
            glm::vec4(float, float, float, float)>() // full
    );

    lua["vec4"]["x"] = &glm::vec4::x;
    lua["vec4"]["y"] = &glm::vec4::y;
    lua["vec4"]["z"] = &glm::vec4::z;
    lua["vec4"]["w"] = &glm::vec4::w;

    // Optional: value_ptr for direct memory access
    lua.set_function("value_ptr", [](glm::vec4& v) {
        return static_cast<void*>(glm::value_ptr(v)); // as lightuserdata
    });
}
