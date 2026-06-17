#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <epoxy/gl.h>

#include <SDL3/SDL.h>

#include <iostream>
#include <string>
#include <stdexcept>

#include "vector_buffer.h"

namespace {

std::runtime_error sdl_error(const std::string& context)
{
    const char* error = SDL_GetError();
    if (error && error[0] != '\0') {
        return std::runtime_error(context + ": " + error);
    }
    return std::runtime_error(context);
}

void ensure_clipboard_video()
{
    if ((SDL_WasInit(SDL_INIT_VIDEO) & SDL_INIT_VIDEO) == 0) {
        SDL_ClearError();
        if (!SDL_InitSubSystem(SDL_INIT_VIDEO)) {
            throw sdl_error("SDL video subsystem required for clipboard");
        }
    }
}

std::string normalize_clipboard_text(const std::string& raw)
{
    std::string result;
    result.reserve(raw.size());
    for (size_t i = 0; i < raw.size(); ++i) {
        if (raw[i] == '\r') {
            if (i + 1 < raw.size() && raw[i + 1] == '\n') {
                ++i;
            }
            result.push_back('\n');
        } else {
            result.push_back(raw[i]);
        }
    }
    return result;
}

sol::table create_gl_table(sol::state_view lua)
{
    sol::table gl = lua.create_table();

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
    gl["GL_TRIANGLE_STRIP"] = GL_TRIANGLE_STRIP;
    gl["GL_LINES"] = GL_LINES;
    gl["GL_LINE_STRIP"] = GL_LINE_STRIP;
    gl["GL_POINTS"] = GL_POINTS;
    gl["GL_DEPTH_BUFFER_BIT"] = GL_DEPTH_BUFFER_BIT;
    gl["GL_DEPTH_TEST"] = GL_DEPTH_TEST;
    gl["GL_PROGRAM_POINT_SIZE"] = GL_PROGRAM_POINT_SIZE;
    gl["GL_LESS"] = GL_LESS;
    gl["GL_ARRAY_BUFFER"] = GL_ARRAY_BUFFER;
    gl["GL_ELEMENT_ARRAY_BUFFER"] = GL_ELEMENT_ARRAY_BUFFER;
    gl["GL_SHADER_STORAGE_BUFFER"] = GL_SHADER_STORAGE_BUFFER;
    gl["GL_STATIC_DRAW"] = GL_STATIC_DRAW;
    gl["GL_STREAM_DRAW"] = GL_STREAM_DRAW;
    gl["GL_TIME_ELAPSED"] = GL_TIME_ELAPSED;
    gl["GL_QUERY_RESULT"] = GL_QUERY_RESULT;
    gl["GL_QUERY_RESULT_AVAILABLE"] = GL_QUERY_RESULT_AVAILABLE;
    gl["GL_FRAMEBUFFER"] = GL_FRAMEBUFFER;
    gl["GL_READ_FRAMEBUFFER"] = GL_READ_FRAMEBUFFER;
    gl["GL_DRAW_FRAMEBUFFER"] = GL_DRAW_FRAMEBUFFER;
    gl["GL_FRONT"] = GL_FRONT;
    gl["GL_BACK"] = GL_BACK;
    gl["GL_RENDERBUFFER"] = GL_RENDERBUFFER;
    gl["GL_FLOAT"] = GL_FLOAT;
    gl["GL_INT"] = GL_INT;
    gl["GL_UNSIGNED_INT"] = GL_UNSIGNED_INT;
    gl["GL_FALSE"] = GL_FALSE;
    gl["GL_TRUE"] = GL_TRUE;
    gl["GL_CULL_FACE"] = GL_CULL_FACE;
    gl["GL_TEXTURE0"] = GL_TEXTURE0;
    gl["GL_TEXTURE_2D"] = GL_TEXTURE_2D;
    gl["GL_TEXTURE_CUBE_MAP"] = GL_TEXTURE_CUBE_MAP;
    gl["GL_TEXTURE_WRAP_S"] = GL_TEXTURE_WRAP_S;
    gl["GL_TEXTURE_WRAP_T"] = GL_TEXTURE_WRAP_T;
    gl["GL_TEXTURE_WRAP_R"] = GL_TEXTURE_WRAP_R;
    gl["GL_TEXTURE_MIN_FILTER"] = GL_TEXTURE_MIN_FILTER;
    gl["GL_TEXTURE_MAG_FILTER"] = GL_TEXTURE_MAG_FILTER;
    gl["GL_CLAMP_TO_EDGE"] = GL_CLAMP_TO_EDGE;
    gl["GL_LINEAR"] = GL_LINEAR;
    gl["GL_NEAREST"] = GL_NEAREST;
    gl["GL_RGB"] = GL_RGB;
    gl["GL_RGBA"] = GL_RGBA;
    gl["GL_RGBA8"] = GL_RGBA8;
    gl["GL_UNSIGNED_BYTE"] = GL_UNSIGNED_BYTE;
    gl["GL_COLOR_ATTACHMENT0"] = GL_COLOR_ATTACHMENT0;
    gl["GL_DEPTH_ATTACHMENT"] = GL_DEPTH_ATTACHMENT;
    gl["GL_DEPTH_COMPONENT"] = GL_DEPTH_COMPONENT;

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

    gl.set_function("glViewport", [](GLint x, GLint y, GLsizei width, GLsizei height) {
        glViewport(x, y, width, height);
    });

    gl.set_function("glClearColor", [](float r, float g, float b, float a) {
        glClearColor(r, g, b, a);
    });

    gl.set_function("glDrawArrays", [](GLenum mode, GLint first, GLsizei count) {
        glDrawArrays(mode, first, count);
    });
    gl.set_function("glDrawArraysInstanced", [](GLenum mode, GLint first, GLsizei count, GLsizei instancecount) {
        glDrawArraysInstanced(mode, first, count, instancecount);
    });
    gl.set_function("glDrawElementsInstanced", [](GLenum mode,
                                                 GLsizei count,
                                                 GLenum type,
                                                 size_t index_offset_bytes,
                                                 GLsizei instancecount) {
        glDrawElementsInstanced(mode,
                                count,
                                type,
                                reinterpret_cast<const void*>(static_cast<uintptr_t>(index_offset_bytes)),
                                instancecount);
    });
    gl.set_function("glMultiDrawArrays", [](GLenum mode,
                                           sol::as_table_t<std::vector<int>> first_list,
                                           sol::as_table_t<std::vector<int>> count_list) {
        const std::vector<int>& firsts = first_list.value();
        const std::vector<int>& counts = count_list.value();
        if (firsts.size() != counts.size()) {
            throw std::runtime_error("glMultiDrawArrays requires matching firsts and counts sizes");
        }
        if (firsts.empty()) {
            return;
        }
        std::vector<GLint> gl_firsts;
        std::vector<GLsizei> gl_counts;
        gl_firsts.reserve(firsts.size());
        gl_counts.reserve(counts.size());
        for (size_t i = 0; i < firsts.size(); ++i) {
            gl_firsts.push_back(static_cast<GLint>(firsts[i]));
            gl_counts.push_back(static_cast<GLsizei>(counts[i]));
        }
        glMultiDrawArrays(mode, gl_firsts.data(), gl_counts.data(), static_cast<GLsizei>(gl_firsts.size()));
    });
    gl.set_function("glReadPixels", [](GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type) {
        if (width <= 0 || height <= 0) {
            return std::string();
        }
        if (type != GL_UNSIGNED_BYTE) {
            throw std::runtime_error("glReadPixels only supports GL_UNSIGNED_BYTE");
        }
        int channels = 0;
        if (format == GL_RGBA) {
            channels = 4;
        } else if (format == GL_RGB) {
            channels = 3;
        } else {
            throw std::runtime_error("glReadPixels only supports GL_RGBA or GL_RGB");
        }
        std::size_t size = static_cast<std::size_t>(width) *
                           static_cast<std::size_t>(height) *
                           static_cast<std::size_t>(channels);
        std::string buffer;
        buffer.resize(size);
        glReadPixels(x, y, width, height, format, type, buffer.data());
        return buffer;
    });
    gl.set_function("glGetTexImage",
        [](GLenum target, GLint level, GLenum format, GLenum type, GLsizei width, GLsizei height) {
            if (width <= 0 || height <= 0) {
                return std::string();
            }
            if (type != GL_UNSIGNED_BYTE) {
                throw std::runtime_error("glGetTexImage only supports GL_UNSIGNED_BYTE");
            }
            int channels = 0;
            if (format == GL_RGBA) {
                channels = 4;
            } else if (format == GL_RGB) {
                channels = 3;
            } else {
                throw std::runtime_error("glGetTexImage only supports GL_RGBA or GL_RGB");
            }
            std::size_t size = static_cast<std::size_t>(width) *
                               static_cast<std::size_t>(height) *
                               static_cast<std::size_t>(channels);
            std::string buffer;
            buffer.resize(size);
            glGetTexImage(target, level, format, type, buffer.data());
            return buffer;
        });
    gl.set_function("glFinish", []() {
        glFinish();
    });
    gl.set_function("glEnableVertexAttribArray", [](GLuint index) {
        glEnableVertexAttribArray(index);
    });
    gl.set_function("glVertexAttribDivisor", [](GLuint index, GLuint divisor) {
        glVertexAttribDivisor(index, divisor);
    });

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
    gl.set_function("glDeleteVertexArrays", [](GLuint array) {
        glDeleteVertexArrays(1, &array);
    });
    gl.set_function("glBindVertexArray", [](GLuint array) {
        glBindVertexArray(array);
    });

    gl.set_function("glGenBuffers", [](GLsizei n) {
        GLuint buffer;
        glGenBuffers(n, &buffer);
        return buffer;
    });
    gl.set_function("glGenQueries", [](GLsizei n) {
        GLuint query;
        glGenQueries(n, &query);
        return query;
    });
    gl.set_function("glDeleteBuffers", [](GLuint buffer) {
        glDeleteBuffers(1, &buffer);
    });
    gl.set_function("glDeleteQueries", [](GLuint query) {
        glDeleteQueries(1, &query);
    });
    gl.set_function("glBeginQuery", [](GLenum target, GLuint id) {
        glBeginQuery(target, id);
    });
    gl.set_function("glEndQuery", [](GLenum target) {
        glEndQuery(target);
    });
    gl.set_function("glGetQueryObjectui64v", [](GLuint id, GLenum pname) {
        GLuint64 value = 0;
        glGetQueryObjectui64v(id, pname, &value);
        return static_cast<lua_Integer>(value);
    });
    gl.set_function("glGetQueryObjectuiv", [](GLuint id, GLenum pname) {
        GLuint value = 0;
        glGetQueryObjectuiv(id, pname, &value);
        return static_cast<lua_Integer>(value);
    });

    gl.set_function("glGenFramebuffers", [](GLsizei n) {
        GLuint framebuffer;
        glGenFramebuffers(n, &framebuffer);
        return framebuffer;
    });
    gl.set_function("glDeleteFramebuffers", [](GLuint framebuffer) {
        glDeleteFramebuffers(1, &framebuffer);
    });
    gl.set_function("glBindFramebuffer", [](GLenum target, GLuint framebuffer) {
        glBindFramebuffer(target, framebuffer);
    });
    gl.set_function("glReadBuffer", [](GLenum src) {
        glReadBuffer(src);
    });

    gl.set_function("glGenRenderbuffers", [](GLsizei n) {
        GLuint renderbuffer;
        glGenRenderbuffers(n, &renderbuffer);
        return renderbuffer;
    });
    gl.set_function("glDeleteRenderbuffers", [](GLuint renderbuffer) {
        glDeleteRenderbuffers(1, &renderbuffer);
    });
    gl.set_function("glBindRenderbuffer", [](GLenum target, GLuint renderbuffer) {
        glBindRenderbuffer(target, renderbuffer);
    });
    gl.set_function("glRenderbufferStorage",
        [](GLenum target, GLenum internalformat, GLsizei width, GLsizei height) {
            glRenderbufferStorage(target, internalformat, width, height);
        });
    gl.set_function("glFramebufferRenderbuffer",
        [](GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) {
            glFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer);
        });
    gl.set_function("glFramebufferTexture2D",
        [](GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
            glFramebufferTexture2D(target, attachment, textarget, texture, level);
        });

    gl.set_function("glActiveTexture", [](GLenum texture) {
        glActiveTexture(texture);
    });
    gl.set_function("glBindTexture", [](GLenum target, GLuint texture) {
        glBindTexture(target, texture);
    });
    gl.set_function("glGenTextures", [](GLsizei n) {
        GLuint texture;
        glGenTextures(n, &texture);
        return texture;
    });
    gl.set_function("glDeleteTextures", [](GLuint texture) {
        glDeleteTextures(1, &texture);
    });
    gl.set_function("glTexImage2D", [](GLenum target, GLint level, GLint internalFormat,
                GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type) {
        glTexImage2D(target, level, internalFormat, width, height, border, format, type, nullptr);
    });
    gl.set_function("glTexParameteri", [](GLenum target, GLenum pname, GLint param) {
        glTexParameteri(target, pname, param);
    });

    gl.set_function("glEnable", [](GLenum cap) {
        glEnable(cap);
    });
    gl.set_function("glDisable", [](GLenum cap) {
        glDisable(cap);
    });
    gl.set_function("glDepthFunc", [](GLenum func) {
        glDepthFunc(func);
    });
    gl.set_function("glDepthMask", [](GLboolean flag) {
        glDepthMask(flag);
    });

    gl.set_function("glBindBuffer", [](GLenum target, GLuint buffer) {
        glBindBuffer(target, buffer);
    });
    gl.set_function("glBindBufferBase", [](GLenum target, GLuint index, GLuint buffer) {
        glBindBufferBase(target, index, buffer);
    });
    gl.set_function("glBufferData", [](GLenum target, sol::as_table_t<std::vector<float>> data, GLenum usage) {
        glBufferData(target, data.value().size() * sizeof(float), data.value().data(), usage);
    });
    gl.set_function("glBufferDataUInt", [](GLenum target, sol::as_table_t<std::vector<uint32_t>> data, GLenum usage) {
        const std::vector<uint32_t>& values = data.value();
        glBufferData(target,
                     static_cast<GLsizeiptr>(values.size() * sizeof(uint32_t)),
                     values.data(),
                     usage);
    });
    gl.set_function("glBufferSubData", [](GLenum target, size_t offset, const std::string& bytes) {
        if (bytes.empty()) {
            return;
        }
        glBufferSubData(target, static_cast<GLintptr>(offset), static_cast<GLsizeiptr>(bytes.size()), bytes.data());
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
    gl.set_function("bufferSubDataFromVectorBuffer",
            [](VectorBuffer& buffer, GLenum target, size_t offset_bytes, size_t size_bytes) {
                if (size_bytes == 0) {
                    return;
                }
                if (offset_bytes % sizeof(float) != 0 || size_bytes % sizeof(float) != 0) {
                    throw std::runtime_error("bufferSubDataFromVectorBuffer requires float-aligned offset/size");
                }
                const size_t used = buffer.used_size();
                if (offset_bytes + size_bytes > used) {
                    throw std::runtime_error("bufferSubDataFromVectorBuffer out of bounds: exceeds used size");
                }
                const char* base = reinterpret_cast<const char*>(buffer.raw_data());
                const char* ptr = base + offset_bytes;
                glBufferSubData(target,
                                static_cast<GLintptr>(offset_bytes),
                                static_cast<GLsizeiptr>(size_bytes),
                                ptr);
            });
    gl.set_function("bufferDataUIntFromVectorBuffer",
            [](VectorBuffer& buffer, GLenum target, GLenum usage) {
                const size_t count = buffer.length();
                std::vector<uint32_t> packed;
                packed.resize(count);
                const float* src = buffer.raw_data();
                for (size_t i = 0; i < count; ++i) {
                    float value = src[i];
                    if (value < 0.0f) {
                        value = 0.0f;
                    }
                    packed[i] = static_cast<uint32_t>(value);
                }
                glBufferData(target,
                             static_cast<GLsizeiptr>(packed.size() * sizeof(uint32_t)),
                             packed.data(),
                             usage);
            });
    gl.set_function("bufferSubDataUIntFromVectorBuffer",
            [](VectorBuffer& buffer, GLenum target, size_t offset_elements, size_t element_count) {
                if (element_count == 0) {
                    return;
                }
                const size_t used = buffer.length();
                if (offset_elements + element_count > used) {
                    throw std::runtime_error("bufferSubDataUIntFromVectorBuffer out of bounds: exceeds used size");
                }
                std::vector<uint32_t> packed;
                packed.resize(element_count);
                const float* src = buffer.raw_data() + offset_elements;
                for (size_t i = 0; i < element_count; ++i) {
                    float value = src[i];
                    if (value < 0.0f) {
                        value = 0.0f;
                    }
                    packed[i] = static_cast<uint32_t>(value);
                }
                glBufferSubData(target,
                                static_cast<GLintptr>(offset_elements * sizeof(uint32_t)),
                                static_cast<GLsizeiptr>(packed.size() * sizeof(uint32_t)),
                                packed.data());
            });
    gl.set_function("glBlitFramebuffer", [](GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1,
                GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter) {
        glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
            });
    gl.set_function("glGetError", glGetError);

    gl.set_function("clipboard-has", []() {
        ensure_clipboard_video();
        SDL_ClearError();
        bool has_text = SDL_HasClipboardText();
        const char* error = SDL_GetError();
        if (!has_text && error && error[0] != '\0') {
            throw sdl_error("SDL_HasClipboardText failed");
        }
        return has_text;
    });

    gl.set_function("clipboard-get", []() {
        ensure_clipboard_video();
        SDL_ClearError();
        char* text = SDL_GetClipboardText();
        if (!text) {
            throw sdl_error("SDL_GetClipboardText failed");
        }
        std::string value = normalize_clipboard_text(text);
        SDL_free(text);
        if (value.empty()) {
            const char* error = SDL_GetError();
            if (error && error[0] != '\0') {
                throw sdl_error("SDL_GetClipboardText failed");
            }
        }
        return value;
    });

    gl.set_function("clipboard-set", [](const std::string& value) {
        ensure_clipboard_video();
        SDL_ClearError();
        if (!SDL_SetClipboardText(value.c_str())) {
            throw sdl_error("SDL_SetClipboardText failed");
        }
        return true;
    });
    return gl;
}

} // namespace

void lua_bind_opengl(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("gl", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_gl_table(lua);
    });
}
