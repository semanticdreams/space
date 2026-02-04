#include <cstring>
#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "vector_buffer.h"

namespace {

sol::table create_vector_buffer_table(sol::state_view lua)
{
    sol::table vector_buffer_table = lua.create_table();
    vector_buffer_table.new_usertype<VectorHandle>("VectorHandle",
        "index", &VectorHandle::index,
        "size", &VectorHandle::size
    );

    sol::usertype<VectorBuffer> vb_type = vector_buffer_table.new_usertype<VectorBuffer>("VectorBuffer",
        sol::no_constructor
    );

    vb_type.set_function("allocate", &VectorBuffer::allocate);
    vb_type.set_function("reallocate", &VectorBuffer::reallocate);
    vb_type.set_function("delete", &VectorBuffer::deleteHandle);
    vb_type.set_function("length", &VectorBuffer::length);
    vb_type.set_function("print", &VectorBuffer::print);
    vb_type.set_function("clear-dirty", &VectorBuffer::clearDirty);
    vb_type.set_function("dirty-range", [](sol::this_state state, VectorBuffer& self) -> sol::variadic_results {
        sol::variadic_results results;
        auto [from, to] = self.dirty_range();
        if (!self.has_dirty()) {
            return results;
        }
        results.push_back(sol::make_object(state, from));
        results.push_back(sol::make_object(state, to));
        return results;
    });

    auto validate_handle_range = [](VectorBuffer& self, const VectorHandle& handle, size_t offset, size_t count, const char* label) {
        if (handle.size == 0) {
            throw std::runtime_error(std::string(label) + " requires a non-empty handle");
        }
        if (offset + count > handle.size) {
            throw std::runtime_error(std::string(label) + " out of bounds: offset exceeds handle size");
        }
        if (handle.index + handle.size > self.length()) {
            throw std::runtime_error(std::string(label) + " invalid handle: index exceeds buffer length");
        }
    };
    auto validate_handle_in_used_range = [](VectorBuffer& self, const VectorHandle& handle, const char* label) {
        if (handle.index + handle.size > self.length()) {
            throw std::runtime_error(std::string(label) + " invalid handle: index exceeds buffer length");
        }
    };

    // View: expose a table-like float array with set/get access
    vb_type.set_function("view", [validate_handle_range](VectorBuffer& self, VectorHandle& handle) {
        validate_handle_range(self, handle, 0, 1, "VectorBuffer.view");
        float* data = self.view(handle);
        size_t size = handle.size;
        return sol::as_table(std::vector<float>(data, data + size));
    });

    // view_ptr: direct access for setting from glm
    vb_type.set_function("view-ptr", [validate_handle_in_used_range](VectorBuffer& self, VectorHandle& handle) {
        validate_handle_in_used_range(self, handle, "VectorBuffer.view-ptr");
        if (handle.size == 0) {
            throw std::runtime_error("VectorBuffer.view-ptr requires a non-empty handle");
        }
        return self.view(handle); // exposed as lightuserdata
    });

    // set_glm_vec4: assign glm::vec4 to offset in view
    vb_type.set_function("set-glm-vec4", [validate_handle_range](VectorBuffer& self, VectorHandle& handle, size_t offset, const glm::vec4& vec) {
        validate_handle_range(self, handle, offset, 4, "VectorBuffer.set-glm-vec4");
        float* v = self.view(handle);
        std::copy(glm::value_ptr(vec), glm::value_ptr(vec) + 4, v + offset);
        self.markDirty(handle.index + offset, 4);
    });
    // set_glm_vec3: assign glm::vec3 to offset in view
    vb_type.set_function("set-glm-vec3", [validate_handle_range](VectorBuffer& self, VectorHandle& handle, size_t offset, const glm::vec3& vec) {
        validate_handle_range(self, handle, offset, 3, "VectorBuffer.set-glm-vec3");
        float* v = self.view(handle);
        std::copy(glm::value_ptr(vec), glm::value_ptr(vec) + 3, v + offset);
        self.markDirty(handle.index + offset, 3);
    });
    vb_type.set_function("set-glm-vec2", [validate_handle_range](VectorBuffer& self, VectorHandle& handle, size_t offset, const glm::vec2& vec) {
        validate_handle_range(self, handle, offset, 2, "VectorBuffer.set-glm-vec2");
        float* v = self.view(handle);
        std::copy(glm::value_ptr(vec), glm::value_ptr(vec) + 2, v + offset);
        self.markDirty(handle.index + offset, 2);
    });
    vb_type.set_function("set-float", [validate_handle_range](VectorBuffer& self, VectorHandle& handle, size_t offset, float value) {
        validate_handle_range(self, handle, offset, 1, "VectorBuffer.set-float");
        float* v = self.view(handle);
        v[offset] = value;
        self.markDirty(handle.index + offset, 1);
    });
    vb_type.set_function("set-floats-from-bytes", [](VectorBuffer& self, VectorHandle& handle, size_t offset,
                                                    const std::string& bytes) {
        if (bytes.empty()) {
            return;
        }
        if (bytes.size() % sizeof(float) != 0) {
            throw std::runtime_error("VectorBuffer.set-floats-from-bytes requires float-aligned byte size");
        }
        size_t float_count = bytes.size() / sizeof(float);
        if (offset + float_count > handle.size) {
            throw std::runtime_error("VectorBuffer.set-floats-from-bytes exceeds handle size");
        }
        if (handle.index + handle.size > self.length()) {
            throw std::runtime_error("VectorBuffer.set-floats-from-bytes invalid handle: index exceeds buffer length");
        }
        float* v = self.view(handle);
        std::memcpy(v + offset, bytes.data(), bytes.size());
        self.markDirty(handle.index + offset, float_count);
    });
    vb_type.set_function("set-floats-batch", [validate_handle_range](VectorBuffer& self,
                                                                    sol::as_table_t<std::vector<VectorHandle>> handles,
                                                                    size_t offset,
                                                                    sol::as_table_t<std::vector<float>> values,
                                                                    size_t stride) {
        const std::vector<VectorHandle>& handle_list = handles.value();
        const std::vector<float>& value_list = values.value();
        if (stride == 0) {
            throw std::runtime_error("VectorBuffer.set-floats-batch requires a non-zero stride");
        }
        if (handle_list.empty()) {
            return;
        }
        size_t required = handle_list.size() * stride;
        if (value_list.size() < required) {
            throw std::runtime_error("VectorBuffer.set-floats-batch missing values for handles");
        }
        for (size_t i = 0; i < handle_list.size(); ++i) {
            const VectorHandle& handle = handle_list[i];
            validate_handle_range(self, handle, offset, stride, "VectorBuffer.set-floats-batch");
            float* v = self.view(const_cast<VectorHandle&>(handle));
            const float* src = value_list.data() + (i * stride);
            std::memcpy(v + offset, src, stride * sizeof(float));
            self.markDirty(handle.index + offset, stride);
        }
    });

    vector_buffer_table.set_function("VectorBuffer", sol::overload(
        []() { return VectorBuffer(); },
        [](size_t size) { return VectorBuffer(size); }
    ));
    return vector_buffer_table;
}

} // namespace

void lua_bind_vector_buffer(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("vector-buffer", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_vector_buffer_table(lua);
    });
}
