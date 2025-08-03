#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "vector_buffer.h"

void lua_bind_vector_buffer(sol::state& lua) {
    lua.new_usertype<VectorHandle>("VectorHandle",
        "index", &VectorHandle::index,
        "size", &VectorHandle::size
    );

    sol::usertype<VectorBuffer> vb_type = lua.new_usertype<VectorBuffer>("VectorBuffer",
        sol::constructors<VectorBuffer(), VectorBuffer(size_t)>()
    );

    vb_type.set_function("allocate", &VectorBuffer::allocate);
    vb_type.set_function("reallocate", &VectorBuffer::reallocate);
    vb_type.set_function("delete", &VectorBuffer::deleteHandle);
    vb_type.set_function("length", &VectorBuffer::length);

    // View: expose a table-like float array with set/get access
    vb_type.set_function("view", [](VectorBuffer& self, VectorHandle& handle) {
        float* data = self.view(handle);
        size_t size = handle.size;

        // Return a Lua table that supports indexing and allows setting from glm::vec4
        return sol::as_table(std::vector<float>(data, data + size));
    });

    // view_ptr: direct access for setting from glm
    vb_type.set_function("view_ptr", [](VectorBuffer& self, VectorHandle& handle) {
        return self.view(handle); // exposed as lightuserdata
    });

    // set_vec4: assign glm::vec4 to offset in view
    vb_type.set_function("set_vec4", [](VectorBuffer& self, VectorHandle& handle, size_t offset, const glm::vec4& vec) {
        float* v = self.view(handle);
        std::copy(glm::value_ptr(vec), glm::value_ptr(vec) + 4, v + offset);
    });
    // set_vec3: assign glm::vec3 to offset in view
    vb_type.set_function("set_vec3", [](VectorBuffer& self, VectorHandle& handle, size_t offset, const glm::vec3& vec) {
        float* v = self.view(handle);
        std::copy(glm::value_ptr(vec), glm::value_ptr(vec) + 3, v + offset);
    });
    vb_type.set_function("set_float", [](VectorBuffer& self, VectorHandle& handle, size_t offset, float value) {
        float* v = self.view(handle);
        v[offset] = value;
    });
}
