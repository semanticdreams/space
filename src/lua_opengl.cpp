#include <sol/sol.hpp>
#include <GL/glew.h>

void lua_bind_opengl(sol::state& lua) {
    sol::table gl = lua.create_named_table("gl");

    gl["GL_COLOR_BUFFER_BIT"] = GL_COLOR_BUFFER_BIT;
    gl["GL_TRIANGLES"] = GL_TRIANGLES;
    gl["GL_DEPTH_BUFFER_BIT"] = GL_DEPTH_BUFFER_BIT;
    gl["GL_DEPTH_TEST"] = GL_DEPTH_TEST;
    gl["GL_LESS"] = GL_LESS;
    gl["GL_ARRAY_BUFFER"] = GL_ARRAY_BUFFER;
    gl["GL_STATIC_DRAW"] = GL_STATIC_DRAW;
    gl["GL_FRAMEBUFFER"] = GL_FRAMEBUFFER;

    gl.set_function("glClear", [](GLbitfield mask) {
        glClear(mask);
    });

    gl.set_function("glClearColor", [](float r, float g, float b, float a) {
        glClearColor(r, g, b, a);
    });

    gl.set_function("glDrawArrays", [](GLenum mode, GLint first, GLsizei count) {
        glDrawArrays(mode, first, count);
    });
    gl.set_function("glEnableVertexAttribArray", glEnableVertexAttribArray);
    gl.set_function("glVertexAttribPointer", glVertexAttribPointer);
    gl.set_function("glGenBuffers", [](GLsizei n) {
        GLuint buffer;
        glGenBuffers(n, &buffer);
        return buffer;
    });

    gl.set_function("glBindFramebuffer", glBindFramebuffer);
    gl.set_function("glEnable", glEnable);
    gl.set_function("glDepthFunc", glDepthFunc);

    gl.set_function("glBindBuffer", glBindBuffer);
    gl.set_function("glBufferData", [](GLenum target, sol::as_table_t<std::vector<float>> data, GLenum usage) {
        glBufferData(target, data.value().size() * sizeof(float), data.value().data(), usage);
    });

}
