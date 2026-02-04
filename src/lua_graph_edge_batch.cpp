#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "vector_buffer.h"

namespace {

void write_triangle_batch(VectorBuffer& buffer,
                          sol::as_table_t<std::vector<VectorHandle>> handles,
                          sol::as_table_t<std::vector<glm::vec3>> starts,
                          sol::as_table_t<std::vector<glm::vec3>> ends,
                          sol::as_table_t<std::vector<glm::vec4>> colors,
                          sol::as_table_t<std::vector<float>> thicknesses,
                          sol::as_table_t<std::vector<float>> depths) {
    const std::vector<VectorHandle>& handle_list = handles.value();
    const std::vector<glm::vec3>& start_list = starts.value();
    const std::vector<glm::vec3>& end_list = ends.value();
    const std::vector<glm::vec4>& color_list = colors.value();
    const std::vector<float>& thickness_list = thicknesses.value();
    const std::vector<float>& depth_list = depths.value();

    const size_t count = handle_list.size();
    if (count == 0) {
        return;
    }
    if (start_list.size() != count || end_list.size() != count || color_list.size() != count ||
        thickness_list.size() != count || depth_list.size() != count) {
        throw std::runtime_error("graph-edge-batch.write-triangle-batch expects matched array sizes");
    }

    for (size_t i = 0; i < count; ++i) {
        const VectorHandle& handle = handle_list[i];
        if (handle.size < 24) {
            throw std::runtime_error("graph-edge-batch.write-triangle-batch requires handle size >= 24");
        }
        if (handle.index + handle.size > buffer.length()) {
            throw std::runtime_error("graph-edge-batch.write-triangle-batch invalid handle: index exceeds buffer length");
        }
        if (handle.index + 24 > buffer.length()) {
            throw std::runtime_error("graph-edge-batch.write-triangle-batch invalid handle: vertex data exceeds buffer length");
        }

        const glm::vec3& start = start_list[i];
        const glm::vec3& end = end_list[i];
        const glm::vec4& color = color_list[i];
        const float thickness = thickness_list[i];
        const float depth = depth_list[i];

        const glm::vec3 delta = end - start;
        const float len = glm::length(delta);
        glm::vec3 v0 = start;
        glm::vec3 v1 = start;
        glm::vec3 v2 = end;

        if (len > 0.0001f) {
            glm::vec3 perp(-delta.y, delta.x, delta.z);
            const float perp_len = glm::length(perp);
            if (perp_len > 0.00001f) {
                perp = glm::normalize(perp);
            } else {
                perp = glm::vec3(0.0f);
            }
            const glm::vec3 start_offset = perp * (thickness * 0.3f);
            v0 = start - start_offset;
            v1 = start + start_offset;
        }

        float* base = buffer.view(const_cast<VectorHandle&>(handle));
        const glm::vec3 verts[3] = {v0, v1, v2};
        for (int v = 0; v < 3; ++v) {
            const size_t offset = static_cast<size_t>(v) * 8;
            std::memcpy(base + offset, glm::value_ptr(verts[v]), sizeof(float) * 3);
            std::memcpy(base + offset + 3, glm::value_ptr(color), sizeof(float) * 4);
            base[offset + 7] = depth;
        }
    }
}

} // namespace

void lua_bind_graph_edge_batch(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("graph-edge-batch", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table mod = lua_view.create_table();
        mod.set_function("write-triangle-batch", &write_triangle_batch);
        return mod;
    });
}
