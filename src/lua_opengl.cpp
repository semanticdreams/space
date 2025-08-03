#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <GL/glew.h>

#include <iostream>

#include "vector_buffer.h"

void lua_bind_opengl(sol::state& lua) {
    sol::table gl = lua.create_named_table("gl");

    // just to prevent accidently calling gl functions with nil values
    sol::table mt = lua.create_table();
    mt["__index"] = [](sol::this_state, sol::object key) -> sol::object {
        std::string k = key.as<std::string>();
        throw std::runtime_error("Access to undefined key: " + k);
        return sol::nil;
    };
    gl[sol::metatable_key] = mt;

    gl["GL_COLOR_BUFFER_BIT"] = GL_COLOR_BUFFER_BIT;
    gl["GL_TRIANGLES"] = GL_TRIANGLES;
    gl["GL_POINTS"] = GL_POINTS;
    gl["GL_DEPTH_BUFFER_BIT"] = GL_DEPTH_BUFFER_BIT;
    gl["GL_DEPTH_TEST"] = GL_DEPTH_TEST;
    gl["GL_LESS"] = GL_LESS;
    gl["GL_ARRAY_BUFFER"] = GL_ARRAY_BUFFER;
    gl["GL_STATIC_DRAW"] = GL_STATIC_DRAW;
    gl["GL_STREAM_DRAW"] = GL_STREAM_DRAW;
    gl["GL_FRAMEBUFFER"] = GL_FRAMEBUFFER;
    gl["GL_FLOAT"] = GL_FLOAT;
    gl["GL_INT"] = GL_INT;
    gl["GL_FALSE"] = GL_FALSE;
    gl["GL_TRUE"] = GL_TRUE;
    gl["GL_CULL_FACE"] = GL_CULL_FACE;

    gl.set_function("checkFramebuffer", []() {
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE) {
            std::cerr << "FBO incomplete: " << std::hex << status << std::endl;
        }
    });

    gl.set_function("glClear", [](GLbitfield mask) {
        glClear(mask);
    });

    gl.set_function("getViewport", []() {
        GLint viewport[4];
        glGetIntegerv(GL_VIEWPORT, viewport);
        return glm::vec4(
                static_cast<float>(viewport[0]),
                static_cast<float>(viewport[1]),
                static_cast<float>(viewport[2]),
                static_cast<float>(viewport[3])
        );
    });

    gl.set_function("glViewport", glViewport);

    gl.set_function("glClearColor", [](float r, float g, float b, float a) {
        glClearColor(r, g, b, a);
    });

    gl.set_function("glDrawArrays", [](GLenum mode, GLint first, GLsizei count) {
        glDrawArrays(mode, first, count);
    });
    gl.set_function("glEnableVertexAttribArray", glEnableVertexAttribArray);

    //gl.set_function("glVertexAttribPointer", glVertexAttribPointer);
    //gl.set_function("glVertexAttribIPointer", glVertexAttribIPointer);

    gl.set_function("glVertexAttribPointer", [](GLuint index, GLint size, GLenum type,
                GLboolean normalized, GLsizei stride, int pointer_offset) {
        glVertexAttribPointer(index, size, type, normalized, stride, reinterpret_cast<const void*>(static_cast<uintptr_t>(pointer_offset)));
            });

    gl.set_function("glVertexAttribIPointer", [](GLuint index, GLint size, GLenum type,
                GLsizei stride, int pointer_offset) {
        glVertexAttribIPointer(index, size, type, stride, reinterpret_cast<const void*>(static_cast<uintptr_t>(pointer_offset)));
            });

    gl.set_function("glGenVertexArrays", [](GLsizei n) {
        GLuint arrays;
        glGenVertexArrays(n, &arrays);
        return arrays;
    });
    gl.set_function("glBindVertexArray", glBindVertexArray);

    gl.set_function("glGenBuffers", [](GLsizei n) {
        GLuint buffer;
        glGenBuffers(n, &buffer);
        return buffer;
    });

    gl.set_function("glBindFramebuffer", glBindFramebuffer);
    gl.set_function("glEnable", glEnable);
    gl.set_function("glDisable", glDisable);
    gl.set_function("glDepthFunc", glDepthFunc);

    gl.set_function("glBindBuffer", glBindBuffer);
    gl.set_function("glBufferData", [](GLenum target, sol::as_table_t<std::vector<float>> data, GLenum usage) {
        glBufferData(target, data.value().size() * sizeof(float), data.value().data(), usage);
    });
    gl.set_function("bufferDataFromVectorBuffer",
            [](VectorBuffer& buffer, GLenum target, GLenum usage) {
            float* data = buffer.raw_data();
            size_t size = buffer.used_size();

            //size_t count = size / sizeof(float);
            //for (size_t i = 0; i < count; ++i) {
            //std::cout << "data[" << i << "] = " << data[i] << std::endl;
            //}

            glBufferData(target, size, data, usage);
            });
    gl.set_function("glGetError", glGetError);
}
