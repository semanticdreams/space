#include <algorithm>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>
#include <limits>

#include <sol/sol.hpp>

#include <glm/glm.hpp>
#include <glm/gtx/quaternion.hpp>

#include <BulletCollision/CollisionShapes/btTriangleMesh.h>

#include "vector_buffer.h"

namespace {

struct ColorStop {
    float height;
    glm::vec4 color;
};

class PerlinTerrainMesh {
public:
    explicit PerlinTerrainMesh(const sol::optional<sol::table>& opts_opt)
    {
        width_ = std::max(2, int_or(opts_opt, "width", 50));
        length_ = std::max(2, int_or(opts_opt, "length", 50));
        seed_ = uint32_or(opts_opt, "seed", 1337u);

        n1div_ = float_or(opts_opt, "n1div", 30.0f);
        n2div_ = float_or(opts_opt, "n2div", 4.0f);
        n3div_ = float_or(opts_opt, "n3div", 1.0f);
        n1scale_ = float_or(opts_opt, "n1scale", 20.0f);
        n2scale_ = float_or(opts_opt, "n2scale", 2.0f);
        n3scale_ = float_or(opts_opt, "n3scale", 1.0f);
        zroot_ = float_or(opts_opt, "zroot", 2.0f);
        zpower_ = float_or(opts_opt, "zpower", 2.5f);

        colors_ = {
            { 0.0f, glm::vec4(0.0f, 0.0f, 1.0f, 1.0f) },
            { 1.0f, glm::vec4(1.0f, 1.0f, 0.0f, 1.0f) },
            { 20.0f, glm::vec4(0.0f, 1.0f, 0.0f, 1.0f) },
            { 25.0f, glm::vec4(0.5f, 0.5f, 0.5f, 1.0f) },
            { 1000.0f, glm::vec4(1.0f, 1.0f, 1.0f, 1.0f) },
        };

        build_permutation(seed_);
        generate_points();
        generate_triangles();
    }

    int width() const { return width_; }
    int length() const { return length_; }
    std::size_t point_count() const { return points_.size(); }
    std::size_t triangle_count() const { return triangles_.size() / 3; }
    std::size_t vertex_count() const { return triangle_count() * 3; }
    std::size_t float_count() const { return vertex_count() * 8; }

    float min_height() const { return min_height_; }
    float max_height() const { return max_height_; }

    float point_height(int x, int z) const
    {
        if (x < 0 || z < 0 || x >= width_ || z >= length_) {
            throw std::runtime_error("PerlinTerrainMesh.point-height out of bounds");
        }
        return points_[std::size_t(x * length_ + z)].y;
    }

    void write_to_vector_buffer(VectorBuffer& vector,
                                VectorHandle& handle,
                                const glm::vec3& position,
                                const glm::quat& rotation,
                                const glm::vec3& scale,
                                float opacity,
                                float depth) const
    {
        if (handle.size != float_count()) {
            throw std::runtime_error("PerlinTerrainMesh.write-to-vector-buffer handle size mismatch");
        }
        if (handle.index + handle.size > vector.length()) {
            throw std::runtime_error("PerlinTerrainMesh.write-to-vector-buffer invalid handle");
        }

        float* out = vector.view(handle);
        std::size_t offset = 0;
        const std::size_t tri_count = triangle_count();
        for (std::size_t tri_i = 0; tri_i < tri_count; ++tri_i) {
            const glm::vec4& base_color = triangle_colors_[tri_i];
            glm::vec4 color(base_color.r, base_color.g, base_color.b, base_color.a * opacity);
            for (int corner = 0; corner < 3; ++corner) {
                uint32_t point_index = triangles_[tri_i * 3 + std::size_t(corner)];
                const glm::vec3& canonical = points_[point_index];
                glm::vec3 scaled(canonical.x * scale.x, canonical.y * scale.y, canonical.z * scale.z);
                glm::vec3 final_pos = position + rotation * scaled;

                out[offset++] = final_pos.x;
                out[offset++] = final_pos.y;
                out[offset++] = final_pos.z;
                out[offset++] = color.r;
                out[offset++] = color.g;
                out[offset++] = color.b;
                out[offset++] = color.a;
                out[offset++] = depth;
            }
        }
        vector.markDirty(handle.index, handle.size);
    }

    void add_to_triangle_mesh(btTriangleMesh& mesh,
                              const glm::vec3& position,
                              const glm::quat& rotation,
                              const glm::vec3& scale,
                              bool remove_duplicate_vertices) const
    {
        const std::size_t tri_count = triangle_count();
        for (std::size_t tri_i = 0; tri_i < tri_count; ++tri_i) {
            glm::vec3 world_vertices[3];
            for (int corner = 0; corner < 3; ++corner) {
                uint32_t point_index = triangles_[tri_i * 3 + std::size_t(corner)];
                const glm::vec3& canonical = points_[point_index];
                glm::vec3 scaled(canonical.x * scale.x, canonical.y * scale.y, canonical.z * scale.z);
                world_vertices[corner] = position + rotation * scaled;
            }
            mesh.addTriangle(btVector3(world_vertices[0].x, world_vertices[0].y, world_vertices[0].z),
                             btVector3(world_vertices[1].x, world_vertices[1].y, world_vertices[1].z),
                             btVector3(world_vertices[2].x, world_vertices[2].y, world_vertices[2].z),
                             remove_duplicate_vertices);
        }
    }

private:
    int width_ { 50 };
    int length_ { 50 };
    uint32_t seed_ { 1337u };

    float n1div_ { 30.0f };
    float n2div_ { 4.0f };
    float n3div_ { 1.0f };
    float n1scale_ { 20.0f };
    float n2scale_ { 2.0f };
    float n3scale_ { 1.0f };
    float zroot_ { 2.0f };
    float zpower_ { 2.5f };

    std::vector<int> permutation_;
    std::vector<glm::vec3> points_;
    std::vector<uint32_t> triangles_;
    std::vector<glm::vec4> triangle_colors_;
    std::vector<ColorStop> colors_;
    float min_height_ { 0.0f };
    float max_height_ { 0.0f };

    static int int_or(const sol::optional<sol::table>& opts, const char* key, int fallback)
    {
        if (!opts) {
            return fallback;
        }
        sol::optional<int> value = (*opts)[key];
        return value ? *value : fallback;
    }

    static uint32_t uint32_or(const sol::optional<sol::table>& opts, const char* key, uint32_t fallback)
    {
        if (!opts) {
            return fallback;
        }
        sol::optional<uint32_t> value = (*opts)[key];
        return value ? *value : fallback;
    }

    static float float_or(const sol::optional<sol::table>& opts, const char* key, float fallback)
    {
        if (!opts) {
            return fallback;
        }
        sol::optional<float> value = (*opts)[key];
        return value ? *value : fallback;
    }

    static float fade(float t)
    {
        return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
    }

    static float lerp(float a, float b, float t)
    {
        return a + t * (b - a);
    }

    static float grad(int hash, float x, float y)
    {
        switch (hash & 7) {
            case 0: return x + y;
            case 1: return -x + y;
            case 2: return x - y;
            case 3: return -x - y;
            case 4: return x;
            case 5: return -x;
            case 6: return y;
            default: return -y;
        }
    }

    void build_permutation(uint32_t seed)
    {
        std::vector<int> p(256);
        std::iota(p.begin(), p.end(), 0);
        std::mt19937 rng(seed);
        std::shuffle(p.begin(), p.end(), rng);
        permutation_.resize(512);
        for (int i = 0; i < 256; ++i) {
            permutation_[i] = p[i];
            permutation_[i + 256] = p[i];
        }
    }

    float noise(float x, float y) const
    {
        int xi = int(std::floor(x)) & 255;
        int yi = int(std::floor(y)) & 255;

        float xf = x - std::floor(x);
        float yf = y - std::floor(y);

        float u = fade(xf);
        float v = fade(yf);

        int aa = permutation_[permutation_[xi] + yi];
        int ab = permutation_[permutation_[xi] + yi + 1];
        int ba = permutation_[permutation_[xi + 1] + yi];
        int bb = permutation_[permutation_[xi + 1] + yi + 1];

        float x1 = lerp(grad(aa, xf, yf), grad(ba, xf - 1.0f, yf), u);
        float x2 = lerp(grad(ab, xf, yf - 1.0f), grad(bb, xf - 1.0f, yf - 1.0f), u);
        return lerp(x1, x2, v);
    }

    float remap_height(float raw) const
    {
        if (raw >= 0.0f) {
            return -std::sqrt(raw);
        }
        float positive = -raw;
        float rooted = std::pow(positive, 1.0f / std::max(1e-6f, zroot_));
        return std::pow(rooted, zpower_);
    }

    glm::vec4 color_for_height(float height) const
    {
        for (const ColorStop& stop : colors_) {
            if (height <= stop.height) {
                return stop.color;
            }
        }
        return colors_.back().color;
    }

    void generate_points()
    {
        points_.clear();
        points_.reserve(std::size_t(width_ * length_));

        const float half_width = float(width_) * 0.5f;
        const float half_length = float(length_) * 0.5f;

        min_height_ = std::numeric_limits<float>::infinity();
        max_height_ = -std::numeric_limits<float>::infinity();

        for (int x = 0; x < width_; ++x) {
            for (int z = 0; z < length_; ++z) {
                float px = float(x) - half_width;
                float pz = float(z) - half_length;
                float x1 = float(x);
                float z1 = float(z);

                float raw =
                    noise(x1 / n1div_, z1 / n1div_) * n1scale_
                    + noise(x1 / n2div_, z1 / n2div_) * n2scale_
                    + noise(x1 / n3div_, z1 / n3div_) * n3scale_;
                float py = remap_height(raw);

                min_height_ = std::min(min_height_, py);
                max_height_ = std::max(max_height_, py);
                points_.emplace_back(px, py, pz);
            }
        }
    }

    void append_triangle(uint32_t a, uint32_t b, uint32_t c)
    {
        triangles_.push_back(a);
        triangles_.push_back(b);
        triangles_.push_back(c);
        float avg = (points_[a].y + points_[b].y + points_[c].y) / 3.0f;
        triangle_colors_.push_back(color_for_height(avg));
    }

    void generate_triangles()
    {
        triangles_.clear();
        triangle_colors_.clear();
        const std::size_t expected = std::size_t(width_ - 1) * std::size_t(length_ - 1) * 2;
        triangles_.reserve(expected * 3);
        triangle_colors_.reserve(expected);

        for (int x = 0; x < width_ - 1; ++x) {
            for (int z = 0; z < length_ - 1; ++z) {
                uint32_t a = uint32_t(x * length_ + z);
                uint32_t b = uint32_t(x * length_ + (z + 1));
                uint32_t c = uint32_t((x + 1) * length_ + z);
                uint32_t d = uint32_t((x + 1) * length_ + (z + 1));

                append_triangle(a, b, c);
                append_triangle(c, b, d);
            }
        }
    }
};

sol::table create_perlin_terrain_table(sol::state_view lua)
{
    sol::table module = lua.create_table();

    module.new_usertype<PerlinTerrainMesh>("PerlinTerrainMesh",
                                           sol::constructors<PerlinTerrainMesh(const sol::optional<sol::table>&)>(),
                                           "width", &PerlinTerrainMesh::width,
                                           "length", &PerlinTerrainMesh::length,
                                           "point-count", &PerlinTerrainMesh::point_count,
                                           "triangle-count", &PerlinTerrainMesh::triangle_count,
                                           "vertex-count", &PerlinTerrainMesh::vertex_count,
                                           "float-count", &PerlinTerrainMesh::float_count,
                                           "min-height", &PerlinTerrainMesh::min_height,
                                           "max-height", &PerlinTerrainMesh::max_height,
                                           "point-height", &PerlinTerrainMesh::point_height,
                                           "write-to-vector-buffer", &PerlinTerrainMesh::write_to_vector_buffer,
                                           "add-to-triangle-mesh", &PerlinTerrainMesh::add_to_triangle_mesh);

    module.set_function("PerlinTerrainMesh", [](const sol::optional<sol::table>& opts) {
        return std::make_unique<PerlinTerrainMesh>(opts);
    });

    return module;
}

} // namespace

void lua_bind_perlin_terrain(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("perlin-terrain-native", [](sol::this_state state) {
        sol::state_view lua_view(state);
        return create_perlin_terrain_table(lua_view);
    });
}
