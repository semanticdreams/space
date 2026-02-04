#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtx/rotate_vector.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>
#include <sol/sol.hpp>

namespace {

sol::table create_glm_table(sol::state_view lua)
{
    sol::table glm_table = lua.create_table();

    // vec2
    glm_table.new_usertype<glm::vec2>("vec2",
        sol::no_constructor,
        "x", &glm::vec2::x,
        "y", &glm::vec2::y,
        sol::meta_function::addition, sol::resolve<glm::vec2(const glm::vec2&, const glm::vec2&)>(&glm::operator+),
        sol::meta_function::subtraction, sol::resolve<glm::vec2(const glm::vec2&, const glm::vec2&)>(&glm::operator-),
        sol::meta_function::multiplication, sol::overload(
            sol::resolve<glm::vec2(const glm::vec2&, const glm::vec2&)>(&glm::operator*),
            [](const glm::vec2& v, float s) { return v * s; },
            [](float s, const glm::vec2& v) { return s * v; }
        ),
        sol::meta_function::division, sol::overload(
            sol::resolve<glm::vec2(const glm::vec2&, const glm::vec2&)>(&glm::operator/),
            [](const glm::vec2& v, float s) { return v / s; },
            [](float s, const glm::vec2& v) { return s / v; }
        )
    );
    glm_table.set_function("vec2", sol::overload(
        []() { return glm::vec2(); },
        [](float v) { return glm::vec2(v); },
        [](float x, float y) { return glm::vec2(x, y); }
    ));

    // vec3
    glm_table.new_usertype<glm::vec3>("vec3",
        sol::no_constructor,
        "x", sol::property(
            [](const glm::vec3& self) { return self.x; },
            [](glm::vec3& self, float value) {
                if (!std::isfinite(value)) {
                    throw sol::error("vec3.x must be finite");
                }
                self.x = value;
                double magnitude = glm::length(self);
                if (!std::isfinite(magnitude) || magnitude > 1e6) {
                    throw sol::error("vec3 magnitude exceeds threshold after setting x");
                }
            }
        ),
        "y", sol::property(
            [](const glm::vec3& self) { return self.y; },
            [](glm::vec3& self, float value) {
                if (!std::isfinite(value)) {
                    throw sol::error("vec3.y must be finite");
                }
                self.y = value;
                double magnitude = glm::length(self);
                if (!std::isfinite(magnitude) || magnitude > 1e6) {
                    throw sol::error("vec3 magnitude exceeds threshold after setting y");
                }
            }
        ),
        "z", sol::property(
            [](const glm::vec3& self) { return self.z; },
            [](glm::vec3& self, float value) {
                if (!std::isfinite(value)) {
                    throw sol::error("vec3.z must be finite");
                }
                self.z = value;
                double magnitude = glm::length(self);
                if (!std::isfinite(magnitude) || magnitude > 1e6) {
                    throw sol::error("vec3 magnitude exceeds threshold after setting z");
                }
            }
        ),

        sol::meta_function::index, [](glm::vec3& self, int i) -> float& {
        if (i < 1 || i > 3) throw sol::error("vec3 index out of range");
        return self[i - 1];  // Lua/Fennel are 1-based, GLM is 0-based
        },
        sol::meta_function::new_index, [](glm::vec3& self, int i, float value) {
        if (i < 1 || i > 3) throw sol::error("vec3 index out of range");
        if (!std::isfinite(value)) {
            throw sol::error("vec3 component must be finite");
        }
        self[i - 1] = value;
        double magnitude = glm::length(self);
        if (!std::isfinite(magnitude) || magnitude > 1e6) {
            throw sol::error("vec3 magnitude exceeds threshold after indexed set");
        }
        },

        sol::meta_function::addition, sol::resolve<glm::vec3(const glm::vec3&, const glm::vec3&)>(&glm::operator+),
        sol::meta_function::subtraction, sol::resolve<glm::vec3(const glm::vec3&, const glm::vec3&)>(&glm::operator-),
        sol::meta_function::multiplication, sol::overload(
            sol::resolve<glm::vec3(const glm::vec3&, const glm::vec3&)>(&glm::operator*),
            [](const glm::vec3& v, float s) { return v * s; },
            [](float s, const glm::vec3& v) { return s * v; }
        ),
        sol::meta_function::division, sol::overload(
            sol::resolve<glm::vec3(const glm::vec3&, const glm::vec3&)>(&glm::operator/),
            [](const glm::vec3& v, float s) { return v / s; },
            [](float s, const glm::vec3& v) { return s / v; }
        ),
        sol::meta_function::to_string, [](const glm::vec3& v) {
        std::ostringstream ss;
        ss << "vec3(" << v.x << ", " << v.y << ", " << v.z << ")";
        return ss.str();
        }
    );
    glm_table.set_function("vec3", sol::overload(
        []() { return glm::vec3(); },
        [](float v) { return glm::vec3(v); },
        [](float x, float y, float z) { return glm::vec3(x, y, z); },
        [](const glm::vec2& v, float z) { return glm::vec3(v, z); }
    ));

    // vec4
    glm_table.new_usertype<glm::vec4>("vec4",
            sol::no_constructor,
            "x", &glm::vec4::x,
            "y", &glm::vec4::y,
            "z", &glm::vec4::z,
            "w", &glm::vec4::w,
            sol::meta_function::addition, sol::resolve<glm::vec4(const glm::vec4&, const glm::vec4&)>(&glm::operator+),
            sol::meta_function::subtraction, sol::resolve<glm::vec4(const glm::vec4&, const glm::vec4&)>(&glm::operator-),
            sol::meta_function::multiplication, sol::overload(
                sol::resolve<glm::vec4(const glm::vec4&, const glm::vec4&)>(&glm::operator*),
                [](const glm::vec4& v, const glm::mat4& m) { return v * m; },
                [](const glm::vec4& v, float s) { return v * s; },
                [](float s, const glm::vec4& v) { return s * v; }
            ),
            sol::meta_function::division, sol::overload(
                sol::resolve<glm::vec4(const glm::vec4&, const glm::vec4&)>(&glm::operator/),
                [](const glm::vec4& v, float s) { return v / s; },
                [](float s, const glm::vec4& v) { return s / v; }
            )
            );
    glm_table.set_function("vec4", sol::overload(
        []() { return glm::vec4(); },
        [](float v) { return glm::vec4(v); },
        [](float x, float y, float z, float w) { return glm::vec4(x, y, z, w); },
        [](const glm::vec2& v, float z, float w) { return glm::vec4(v, z, w); },
        [](const glm::vec3& v, float w) { return glm::vec4(v, w); }
    ));

    glm_table.new_usertype<glm::quat>("quat",
            sol::no_constructor,
            "x", &glm::quat::x,
            "y", &glm::quat::y,
            "z", &glm::quat::z,
            "w", &glm::quat::w,

            // Operators
            sol::meta_function::addition, sol::resolve<glm::quat(const glm::quat&, const glm::quat&)>(&glm::operator+),
            sol::meta_function::subtraction, sol::resolve<glm::quat(const glm::quat&, const glm::quat&)>(&glm::operator-),
            sol::meta_function::multiplication, sol::resolve<glm::quat(const glm::quat&, const glm::quat&)>(&glm::operator*),
            //sol::meta_function::division, sol::resolve<glm::quat(const glm::quat&, const glm::quat&)>(&glm::operator/),

            // Useful member functions
            "normalize", [](const glm::quat& q) { return glm::normalize(q); },
            "length", [](const glm::quat& q) { return glm::length(q); },
            "conjugate", [](const glm::quat& q) { return glm::conjugate(q); },
            "inverse", [](const glm::quat& q) { return glm::inverse(q); },

            // Apply rotation
            "rotate", [](const glm::quat& q, const glm::vec3& v) { return q * v; }
    );
    glm_table.set_function("quat", sol::overload(
        []() { return glm::quat(); },
        [](float w, float x, float y, float z) { return glm::quat(w, x, y, z); },
        [](const glm::vec3& eulerAngles) { return glm::quat(eulerAngles); }, // from Euler angles
        [](float angleRadians, const glm::vec3& axis) { return glm::angleAxis(angleRadians, glm::normalize(axis)); } // angle-axis
    ));

    // mat4
    glm_table.new_usertype<glm::mat4>("mat4",
        sol::no_constructor,
        sol::meta_function::multiplication, sol::overload(
            sol::resolve<glm::mat4(const glm::mat4&, const glm::mat4&)>(&glm::operator*),
            [](const glm::mat4& m, const glm::vec4& v) { return m * v; },
            [](const glm::vec4& v, const glm::mat4& m) { return v * m; },
            [](const glm::mat4& m, float s) { return m * s; },
            [](float s, const glm::mat4& m) { return s * m; }
        )
    );
    glm_table.set_function("mat4", sol::overload(
        []() { return glm::mat4(1.0f); },         // identity by default
        [](float diag) { return glm::mat4(diag); } // diagonal matrix
    ));

    // Vector functions
    glm_table.set_function("normalize", sol::overload(
        static_cast<glm::vec2(*)(const glm::vec2&)>(&glm::normalize),
        static_cast<glm::vec3(*)(const glm::vec3&)>(&glm::normalize),
        static_cast<glm::vec4(*)(const glm::vec4&)>(&glm::normalize)
    ));

    glm_table.set_function("dot", sol::overload(
        static_cast<float(*)(const glm::vec2&, const glm::vec2&)>(&glm::dot),
        static_cast<float(*)(const glm::vec3&, const glm::vec3&)>(&glm::dot),
        static_cast<float(*)(const glm::vec4&, const glm::vec4&)>(&glm::dot)
    ));

    glm_table.set_function("cross", static_cast<glm::vec3(*)(const glm::vec3&, const glm::vec3&)>(&glm::cross));
    glm_table.set_function("length", sol::overload(
        static_cast<float(*)(const glm::vec2&)>(&glm::length),
        static_cast<float(*)(const glm::vec3&)>(&glm::length),
        static_cast<float(*)(const glm::vec4&)>(&glm::length)
    ));

    // Transform functions
    glm_table.set_function("translate", [](const glm::mat4& mat, const glm::vec3& v) {
        return glm::translate(mat, v);
    });

    glm_table.set_function("rotate", [](const glm::mat4& mat, float angleRadians, const glm::vec3& axis) {
        return glm::rotate(mat, angleRadians, axis);
    });

    glm_table.set_function("scale", [](const glm::mat4& mat, const glm::vec3& v) {
        return glm::scale(mat, v);
    });

    glm_table.set_function("strip-translation", [](glm::mat4 mat) {
        mat[3][0] = 0.0f;
        mat[3][1] = 0.0f;
        mat[3][2] = 0.0f;
        return mat;
    });

    // Projection functions
    glm_table.set_function("perspective", [](float fovRadians, float aspectRatio, float nearPlane, float farPlane) {
        return glm::perspective(fovRadians, aspectRatio, nearPlane, farPlane);
    });

    glm_table.set_function("ortho", [](float left, float right, float bottom, float top, float nearPlane, float farPlane) {
        return glm::ortho(left, right, bottom, top, nearPlane, farPlane);
    });

    glm_table.set_function("lookAt", [](const glm::vec3& eye, const glm::vec3& center, const glm::vec3& up) {
        return glm::lookAt(eye, center, up);
    });

    glm_table.set_function("unproject", [](const glm::vec3& win, const glm::mat4& view, const glm::mat4& projection, const glm::vec4& viewport) {
        return glm::unProject(win, view, projection, viewport);
    });

    glm_table.set_function("project", [](const glm::vec3& obj, const glm::mat4& view, const glm::mat4& projection, const glm::vec4& viewport) {
        return glm::project(obj, view, projection, viewport);
    });

    // Optional: raw pointers for OpenGL interop
    glm_table.set_function("value-ptr-vec2", [](glm::vec2& v) { return static_cast<void*>(glm::value_ptr(v)); });
    glm_table.set_function("value-ptr-vec3", [](glm::vec3& v) { return static_cast<void*>(glm::value_ptr(v)); });
    glm_table.set_function("value-ptr-vec4", [](glm::vec4& v) { return static_cast<void*>(glm::value_ptr(v)); });
    glm_table.set_function("value-ptr-mat4", [](glm::mat4& m) { return static_cast<void*>(glm::value_ptr(m)); });
    return glm_table;
}

} // namespace

void lua_bind_glm(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("glm", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_glm_table(lua);
    });
}
