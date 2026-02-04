#include "cgltf_jobs.h"

#include <limits>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "cgltf.h"
#include "gltf_mesh_job.h"
#include "job_system.h"

namespace {

const char* cgltf_result_to_string(cgltf_result result)
{
    switch (result) {
    case cgltf_result_success:
        return "success";
    case cgltf_result_data_too_short:
        return "data-too-short";
    case cgltf_result_unknown_format:
        return "unknown-format";
    case cgltf_result_invalid_json:
        return "invalid-json";
    case cgltf_result_invalid_gltf:
        return "invalid-gltf";
    case cgltf_result_invalid_options:
        return "invalid-options";
    case cgltf_result_file_not_found:
        return "file-not-found";
    case cgltf_result_io_error:
        return "io-error";
    case cgltf_result_out_of_memory:
        return "out-of-memory";
    case cgltf_result_legacy_gltf:
        return "legacy-gltf";
    case cgltf_result_max_enum:
        return "max";
    }
    return "unknown";
}

JobSystem::JobResult make_error(const JobSystem::JobRequest& req, const std::string& message)
{
    JobSystem::JobResult result {};
    result.id = req.id;
    result.kind = req.kind;
    result.ok = false;
    result.error = message;
    return result;
}

std::string copy_buffer_view(const cgltf_buffer_view* view)
{
    if (!view) {
        return {};
    }
    const char* start = nullptr;
    if (view->data) {
        start = static_cast<const char*>(view->data);
    } else if (view->buffer && view->buffer->data) {
        start = static_cast<const char*>(view->buffer->data) + view->offset;
    }
    if (!start || view->size == 0) {
        return {};
    }
    return std::string(start, start + view->size);
}

const cgltf_attribute* find_attribute(const cgltf_attribute* attributes,
                                      cgltf_size count,
                                      cgltf_attribute_type type,
                                      int index)
{
    for (cgltf_size i = 0; i < count; ++i) {
        if (attributes[i].type == type && attributes[i].index == index) {
            return &attributes[i];
        }
    }
    return nullptr;
}

std::optional<cgltf_size> index_of(const cgltf_image* image, const cgltf_image* base, cgltf_size count)
{
    if (!image || !base || count == 0) {
        return std::nullopt;
    }
    auto offset = image - base;
    if (offset < 0 || static_cast<cgltf_size>(offset) >= count) {
        return std::nullopt;
    }
    return static_cast<cgltf_size>(offset + 1);
}

JobSystem::JobResult build_mesh_batches(const JobSystem::JobRequest& req)
{
    if (req.payload.empty()) {
        return make_error(req, "cgltf.build-mesh-batches requires a path payload");
    }

    cgltf_options options {};
    cgltf_data* data = nullptr;
    cgltf_result parsed = cgltf_parse_file(&options, req.payload.c_str(), &data);
    if (parsed != cgltf_result_success) {
        std::string message = "cgltf.parse-file failed: ";
        message += cgltf_result_to_string(parsed);
        return make_error(req, message);
    }

    cgltf_result loaded = cgltf_load_buffers(&options, data, req.payload.c_str());
    if (loaded != cgltf_result_success) {
        std::string message = "cgltf.load-buffers failed: ";
        message += cgltf_result_to_string(loaded);
        cgltf_free(data);
        return make_error(req, message);
    }

    auto result_data = std::make_unique<GltfMeshJobResult>();
    result_data->has_bounds = false;
    result_data->bounds_min[0] = result_data->bounds_min[1] = result_data->bounds_min[2] =
        std::numeric_limits<float>::infinity();
    result_data->bounds_max[0] = result_data->bounds_max[1] = result_data->bounds_max[2] =
        -std::numeric_limits<float>::infinity();

    for (cgltf_size mesh_index = 0; mesh_index < data->meshes_count; ++mesh_index) {
        const cgltf_mesh& mesh = data->meshes[mesh_index];
        for (cgltf_size prim_index = 0; prim_index < mesh.primitives_count; ++prim_index) {
            const cgltf_primitive& prim = mesh.primitives[prim_index];
            const cgltf_attribute* position_attr = find_attribute(prim.attributes, prim.attributes_count,
                                                                  cgltf_attribute_type_position, 0);
            const cgltf_attribute* normal_attr = find_attribute(prim.attributes, prim.attributes_count,
                                                                cgltf_attribute_type_normal, 0);
            const cgltf_attribute* texcoord_attr = find_attribute(prim.attributes, prim.attributes_count,
                                                                  cgltf_attribute_type_texcoord, 0);

            if (!position_attr || !position_attr->data) {
                cgltf_free(data);
                return make_error(req, "gltf primitive missing position attribute");
            }
            if (!normal_attr || !normal_attr->data) {
                cgltf_free(data);
                return make_error(req, "gltf primitive missing normal attribute");
            }
            if (!texcoord_attr || !texcoord_attr->data) {
                cgltf_free(data);
                return make_error(req, "gltf primitive missing texcoord attribute");
            }

            const cgltf_accessor* positions_accessor = position_attr->data;
            const cgltf_accessor* normals_accessor = normal_attr->data;
            const cgltf_accessor* uvs_accessor = texcoord_attr->data;
            const cgltf_size vertex_count = positions_accessor->count;
            if (vertex_count == 0) {
                continue;
            }

            std::vector<float> positions(vertex_count * 3);
            std::vector<float> normals(vertex_count * 3);
            std::vector<float> uvs(vertex_count * 2);
            cgltf_accessor_unpack_floats(positions_accessor, positions.data(), positions.size());
            cgltf_accessor_unpack_floats(normals_accessor, normals.data(), normals.size());
            cgltf_accessor_unpack_floats(uvs_accessor, uvs.data(), uvs.size());

            for (cgltf_size v = 0; v < vertex_count; ++v) {
                const cgltf_size pos_offset = v * 3;
                float px = positions[pos_offset];
                float py = positions[pos_offset + 1];
                float pz = positions[pos_offset + 2];
                if (!result_data->has_bounds) {
                    result_data->bounds_min[0] = px;
                    result_data->bounds_min[1] = py;
                    result_data->bounds_min[2] = pz;
                    result_data->bounds_max[0] = px;
                    result_data->bounds_max[1] = py;
                    result_data->bounds_max[2] = pz;
                    result_data->has_bounds = true;
                } else {
                    result_data->bounds_min[0] = std::min(result_data->bounds_min[0], px);
                    result_data->bounds_min[1] = std::min(result_data->bounds_min[1], py);
                    result_data->bounds_min[2] = std::min(result_data->bounds_min[2], pz);
                    result_data->bounds_max[0] = std::max(result_data->bounds_max[0], px);
                    result_data->bounds_max[1] = std::max(result_data->bounds_max[1], py);
                    result_data->bounds_max[2] = std::max(result_data->bounds_max[2], pz);
                }
            }

            std::vector<cgltf_size> indices;
            const cgltf_accessor* indices_accessor = prim.indices;
            if (indices_accessor) {
                indices.resize(indices_accessor->count);
                for (cgltf_size i = 0; i < indices_accessor->count; ++i) {
                    indices[i] = cgltf_accessor_read_index(indices_accessor, i);
                }
            }

            cgltf_size draw_count = indices_accessor ? indices_accessor->count : vertex_count;
            std::vector<float> vertices;
            vertices.reserve(draw_count * 8);

            for (cgltf_size i = 0; i < draw_count; ++i) {
                cgltf_size idx = indices_accessor ? indices[i] : i;
                if (idx >= vertex_count) {
                    cgltf_free(data);
                    return make_error(req, "gltf indices out of range");
                }
                const cgltf_size pos_offset = idx * 3;
                const cgltf_size uv_offset = idx * 2;
                vertices.push_back(uvs[uv_offset]);
                vertices.push_back(uvs[uv_offset + 1]);
                vertices.push_back(normals[pos_offset]);
                vertices.push_back(normals[pos_offset + 1]);
                vertices.push_back(normals[pos_offset + 2]);
                vertices.push_back(positions[pos_offset]);
                vertices.push_back(positions[pos_offset + 1]);
                vertices.push_back(positions[pos_offset + 2]);
            }

            const cgltf_material* material = prim.material;
            if (!material) {
                cgltf_free(data);
                return make_error(req, "gltf primitive missing material");
            }

            const cgltf_texture* texture = material->pbr_metallic_roughness.base_color_texture.texture;
            if (!texture || !texture->image) {
                cgltf_free(data);
                return make_error(req, "gltf material missing base color texture");
            }

            const cgltf_image* image = texture->image;
            std::optional<cgltf_size> image_index = index_of(image, data->images, data->images_count);
            if (!image_index) {
                cgltf_free(data);
                return make_error(req, "gltf texture image index out of range");
            }

            GltfMeshBatch batch {};
            batch.vertices = std::move(vertices);
            batch.image_index = static_cast<int>(*image_index);
            if (image->uri) {
                std::string uri(image->uri);
                if (uri.rfind("data:", 0) == 0) {
                    cgltf_free(data);
                    return make_error(req, "data: image URIs are not supported for gltf textures");
                }
                batch.image_uri = std::move(uri);
            } else if (image->buffer_view) {
                batch.image_bytes = copy_buffer_view(image->buffer_view);
                if (batch.image_bytes.empty()) {
                    cgltf_free(data);
                    return make_error(req, "gltf image buffer view missing data");
                }
            } else {
                cgltf_free(data);
                return make_error(req, "gltf image missing uri or buffer view");
            }

            result_data->batches.emplace_back(std::move(batch));
        }
    }

    cgltf_free(data);

    JobSystem::JobResult result {};
    result.id = req.id;
    result.kind = req.kind;
    result.ok = true;
    result.payload = JobSystem::NativePayload::from_owned(
        result_data.release(),
        0,
        alignof(GltfMeshJobResult),
        sizeof(GltfMeshJobResult),
        [](void* raw) { delete static_cast<GltfMeshJobResult*>(raw); });
    return result;
}

} // namespace

void register_cgltf_job_handlers(JobSystem& jobs)
{
    jobs.register_handler("load_gltf",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              if (req.payload.empty()) {
                                  return make_error(req, "cgltf.load_gltf requires a path payload");
                              }

                              cgltf_options options {};
                              cgltf_data* data = nullptr;
                              cgltf_result parsed = cgltf_parse_file(&options, req.payload.c_str(), &data);
                              if (parsed != cgltf_result_success) {
                                  std::string message = "cgltf.parse-file failed: ";
                                  message += cgltf_result_to_string(parsed);
                                  return make_error(req, message);
                              }

                              cgltf_result loaded = cgltf_load_buffers(&options, data, req.payload.c_str());
                              if (loaded != cgltf_result_success) {
                                  std::string message = "cgltf.load-buffers failed: ";
                                  message += cgltf_result_to_string(loaded);
                                  cgltf_free(data);
                                  return make_error(req, message);
                              }

                              JobSystem::JobResult result {};
                              result.id = req.id;
                              result.kind = req.kind;
                              result.ok = true;
                              result.payload = JobSystem::NativePayload::from_owned(
                                  data,
                                  0,
                                  alignof(cgltf_data),
                                  sizeof(cgltf_data),
                                  [](void* raw) { cgltf_free(static_cast<cgltf_data*>(raw)); });
                              return result;
                          });

    jobs.register_handler("build_gltf_batches", build_mesh_batches);
}
