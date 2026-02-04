#include "lua_cgltf.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "cgltf.h"

CgltfDataHandle::CgltfDataHandle(cgltf_data* data_ptr)
    : data(data_ptr, cgltf_free)
{
}

cgltf_data* CgltfDataHandle::get() const
{
    return data.get();
}

bool CgltfDataHandle::valid() const
{
    return data != nullptr;
}

void CgltfDataHandle::drop()
{
    data.reset();
}

CgltfDataHandle cgltf_adopt_data(cgltf_data* data_ptr)
{
    return CgltfDataHandle(data_ptr);
}

namespace {

struct CgltfLuaContext {
    sol::function file_read;
    sol::function file_release;
    sol::function memory_alloc;
    sol::function memory_free;
    sol::object file_user_data;
    sol::object memory_user_data;
    std::string last_error;
};

struct ParsedCgltfOptions {
    cgltf_options options {};
    CgltfLuaContext context;
};

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

const char* cgltf_file_type_to_string(cgltf_file_type type)
{
    switch (type) {
    case cgltf_file_type_invalid:
        return "auto";
    case cgltf_file_type_gltf:
        return "gltf";
    case cgltf_file_type_glb:
        return "glb";
    case cgltf_file_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_buffer_view_type_to_string(cgltf_buffer_view_type type)
{
    switch (type) {
    case cgltf_buffer_view_type_invalid:
        return "invalid";
    case cgltf_buffer_view_type_indices:
        return "indices";
    case cgltf_buffer_view_type_vertices:
        return "vertices";
    case cgltf_buffer_view_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_attribute_type_to_string(cgltf_attribute_type type)
{
    switch (type) {
    case cgltf_attribute_type_invalid:
        return "invalid";
    case cgltf_attribute_type_position:
        return "position";
    case cgltf_attribute_type_normal:
        return "normal";
    case cgltf_attribute_type_tangent:
        return "tangent";
    case cgltf_attribute_type_texcoord:
        return "texcoord";
    case cgltf_attribute_type_color:
        return "color";
    case cgltf_attribute_type_joints:
        return "joints";
    case cgltf_attribute_type_weights:
        return "weights";
    case cgltf_attribute_type_custom:
        return "custom";
    case cgltf_attribute_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_component_type_to_string(cgltf_component_type type)
{
    switch (type) {
    case cgltf_component_type_invalid:
        return "invalid";
    case cgltf_component_type_r_8:
        return "r-8";
    case cgltf_component_type_r_8u:
        return "r-8u";
    case cgltf_component_type_r_16:
        return "r-16";
    case cgltf_component_type_r_16u:
        return "r-16u";
    case cgltf_component_type_r_32u:
        return "r-32u";
    case cgltf_component_type_r_32f:
        return "r-32f";
    case cgltf_component_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_type_to_string(cgltf_type type)
{
    switch (type) {
    case cgltf_type_invalid:
        return "invalid";
    case cgltf_type_scalar:
        return "scalar";
    case cgltf_type_vec2:
        return "vec2";
    case cgltf_type_vec3:
        return "vec3";
    case cgltf_type_vec4:
        return "vec4";
    case cgltf_type_mat2:
        return "mat2";
    case cgltf_type_mat3:
        return "mat3";
    case cgltf_type_mat4:
        return "mat4";
    case cgltf_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_primitive_type_to_string(cgltf_primitive_type type)
{
    switch (type) {
    case cgltf_primitive_type_points:
        return "points";
    case cgltf_primitive_type_lines:
        return "lines";
    case cgltf_primitive_type_line_loop:
        return "line-loop";
    case cgltf_primitive_type_line_strip:
        return "line-strip";
    case cgltf_primitive_type_triangles:
        return "triangles";
    case cgltf_primitive_type_triangle_strip:
        return "triangle-strip";
    case cgltf_primitive_type_triangle_fan:
        return "triangle-fan";
    case cgltf_primitive_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_alpha_mode_to_string(cgltf_alpha_mode mode)
{
    switch (mode) {
    case cgltf_alpha_mode_opaque:
        return "opaque";
    case cgltf_alpha_mode_mask:
        return "mask";
    case cgltf_alpha_mode_blend:
        return "blend";
    case cgltf_alpha_mode_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_animation_path_to_string(cgltf_animation_path_type type)
{
    switch (type) {
    case cgltf_animation_path_type_invalid:
        return "invalid";
    case cgltf_animation_path_type_translation:
        return "translation";
    case cgltf_animation_path_type_rotation:
        return "rotation";
    case cgltf_animation_path_type_scale:
        return "scale";
    case cgltf_animation_path_type_weights:
        return "weights";
    case cgltf_animation_path_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_interpolation_to_string(cgltf_interpolation_type type)
{
    switch (type) {
    case cgltf_interpolation_type_linear:
        return "linear";
    case cgltf_interpolation_type_step:
        return "step";
    case cgltf_interpolation_type_cubic_spline:
        return "cubic-spline";
    case cgltf_interpolation_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_camera_type_to_string(cgltf_camera_type type)
{
    switch (type) {
    case cgltf_camera_type_invalid:
        return "invalid";
    case cgltf_camera_type_perspective:
        return "perspective";
    case cgltf_camera_type_orthographic:
        return "orthographic";
    case cgltf_camera_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_light_type_to_string(cgltf_light_type type)
{
    switch (type) {
    case cgltf_light_type_invalid:
        return "invalid";
    case cgltf_light_type_directional:
        return "directional";
    case cgltf_light_type_point:
        return "point";
    case cgltf_light_type_spot:
        return "spot";
    case cgltf_light_type_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_data_free_method_to_string(cgltf_data_free_method method)
{
    switch (method) {
    case cgltf_data_free_method_none:
        return "none";
    case cgltf_data_free_method_file_release:
        return "file-release";
    case cgltf_data_free_method_memory_free:
        return "memory-free";
    case cgltf_data_free_method_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_meshopt_mode_to_string(cgltf_meshopt_compression_mode mode)
{
    switch (mode) {
    case cgltf_meshopt_compression_mode_invalid:
        return "invalid";
    case cgltf_meshopt_compression_mode_attributes:
        return "attributes";
    case cgltf_meshopt_compression_mode_triangles:
        return "triangles";
    case cgltf_meshopt_compression_mode_indices:
        return "indices";
    case cgltf_meshopt_compression_mode_max_enum:
        return "max";
    }
    return "unknown";
}

const char* cgltf_meshopt_filter_to_string(cgltf_meshopt_compression_filter filter)
{
    switch (filter) {
    case cgltf_meshopt_compression_filter_none:
        return "none";
    case cgltf_meshopt_compression_filter_octahedral:
        return "octahedral";
    case cgltf_meshopt_compression_filter_quaternion:
        return "quaternion";
    case cgltf_meshopt_compression_filter_exponential:
        return "exponential";
    case cgltf_meshopt_compression_filter_max_enum:
        return "max";
    }
    return "unknown";
}

cgltf_file_type parse_file_type(const sol::object& obj)
{
    if (!obj.valid() || obj.is<sol::nil_t>()) {
        return cgltf_file_type_invalid;
    }
    if (obj.is<cgltf_file_type>()) {
        return obj.as<cgltf_file_type>();
    }
    if (obj.is<int>()) {
        return static_cast<cgltf_file_type>(obj.as<int>());
    }
    if (obj.is<std::string>()) {
        std::string value = obj.as<std::string>();
        if (value == "auto") {
            return cgltf_file_type_invalid;
        }
        if (value == "gltf") {
            return cgltf_file_type_gltf;
        }
        if (value == "glb") {
            return cgltf_file_type_glb;
        }
        throw sol::error("cgltf.options.type invalid value: " + value);
    }
    throw sol::error("cgltf.options.type must be a string or integer");
}

cgltf_result parse_result_value(const sol::object& obj)
{
    if (!obj.valid() || obj.is<sol::nil_t>()) {
        return cgltf_result_success;
    }
    if (obj.is<int>()) {
        return static_cast<cgltf_result>(obj.as<int>());
    }
    if (obj.is<std::string>()) {
        std::string value = obj.as<std::string>();
        if (value == "success") {
            return cgltf_result_success;
        }
        if (value == "data-too-short") {
            return cgltf_result_data_too_short;
        }
        if (value == "unknown-format") {
            return cgltf_result_unknown_format;
        }
        if (value == "invalid-json") {
            return cgltf_result_invalid_json;
        }
        if (value == "invalid-gltf") {
            return cgltf_result_invalid_gltf;
        }
        if (value == "invalid-options") {
            return cgltf_result_invalid_options;
        }
        if (value == "file-not-found") {
            return cgltf_result_file_not_found;
        }
        if (value == "io-error") {
            return cgltf_result_io_error;
        }
        if (value == "out-of-memory") {
            return cgltf_result_out_of_memory;
        }
        if (value == "legacy-gltf") {
            return cgltf_result_legacy_gltf;
        }
        throw sol::error("cgltf.result invalid value: " + value);
    }
    throw sol::error("cgltf.result must be a string or integer");
}

void* cgltf_lua_memory_alloc(void* user, cgltf_size size)
{
    auto* context = static_cast<CgltfLuaContext*>(user);
    if (!context || !context->memory_alloc.valid()) {
        return std::malloc(size);
    }

    sol::protected_function fn = context->memory_alloc;
    sol::protected_function_result result = fn(size, context->memory_user_data);
    if (!result.valid()) {
        sol::error err = result;
        context->last_error = err.what();
        return nullptr;
    }

    sol::object obj = result;
    if (!obj.is<sol::lightuserdata>()) {
        context->last_error = "cgltf.memory.alloc must return lightuserdata";
        return nullptr;
    }

    return obj.as<void*>();
}

void cgltf_lua_memory_free(void* user, void* ptr)
{
    auto* context = static_cast<CgltfLuaContext*>(user);
    if (context && context->memory_free.valid()) {
        sol::protected_function fn = context->memory_free;
        sol::protected_function_result result = fn(ptr, context->memory_user_data);
        if (!result.valid()) {
            sol::error err = result;
            context->last_error = err.what();
        }
        return;
    }
    std::free(ptr);
}

cgltf_result cgltf_lua_file_read(const cgltf_memory_options* memory_options, const cgltf_file_options* file_options,
    const char* path, cgltf_size* size, void** data)
{
    if (!file_options || !file_options->user_data) {
        return cgltf_result_invalid_options;
    }

    auto* context = static_cast<CgltfLuaContext*>(file_options->user_data);
    if (!context || !context->file_read.valid()) {
        return cgltf_result_invalid_options;
    }

    sol::protected_function fn = context->file_read;
    sol::protected_function_result result = fn(path, context->file_user_data);
    if (!result.valid()) {
        sol::error err = result;
        context->last_error = err.what();
        return cgltf_result_io_error;
    }

    sol::object obj = result;
    cgltf_result read_result = cgltf_result_success;
    std::string payload;

    if (obj.is<std::string>()) {
        payload = obj.as<std::string>();
    } else if (obj.is<sol::table>()) {
        sol::table tbl = obj.as<sol::table>();
        sol::optional<sol::object> res_obj = tbl["result"];
        if (res_obj) {
            read_result = parse_result_value(*res_obj);
        }
        sol::optional<std::string> data_obj = tbl["data"];
        if (!data_obj) {
            context->last_error = "cgltf.file.read returned table without data";
            return cgltf_result_io_error;
        }
        payload = *data_obj;
    } else {
        context->last_error = "cgltf.file.read must return string or {result,data}";
        return cgltf_result_io_error;
    }

    if (read_result != cgltf_result_success) {
        return read_result;
    }

    void* out = nullptr;
    if (memory_options && memory_options->alloc_func) {
        out = memory_options->alloc_func(memory_options->user_data, payload.size());
    } else {
        out = std::malloc(payload.size());
    }

    if (!out) {
        return cgltf_result_out_of_memory;
    }

    std::memcpy(out, payload.data(), payload.size());
    *size = payload.size();
    *data = out;
    return cgltf_result_success;
}

void cgltf_lua_file_release(const cgltf_memory_options* memory_options, const cgltf_file_options* file_options, void* data)
{
    if (!data) {
        return;
    }

    if (file_options && file_options->user_data) {
        auto* context = static_cast<CgltfLuaContext*>(file_options->user_data);
        if (context && context->file_release.valid()) {
            sol::protected_function fn = context->file_release;
            sol::protected_function_result result = fn(data, context->file_user_data);
            if (!result.valid()) {
                sol::error err = result;
                context->last_error = err.what();
            }
            return;
        }
    }

    if (memory_options && memory_options->free_func) {
        memory_options->free_func(memory_options->user_data, data);
        return;
    }

    std::free(data);
}

ParsedCgltfOptions parse_cgltf_options(sol::state_view lua, const sol::object& options_obj)
{
    ParsedCgltfOptions parsed {};
    parsed.options = {};
    parsed.options.memory = {};
    parsed.options.file = {};
    parsed.options.type = cgltf_file_type_invalid;
    parsed.options.json_token_count = 0;

    if (!options_obj.is<sol::table>()) {
        return parsed;
    }

    sol::table options = options_obj.as<sol::table>();
    parsed.options.type = parse_file_type(options["type"]);

    sol::optional<cgltf_size> json_tokens = options["json-token-count"];
    if (!json_tokens) {
        json_tokens = options["json_token_count"];
    }
    if (json_tokens) {
        parsed.options.json_token_count = *json_tokens;
    }

    sol::object memory_obj = options["memory"];
    if (memory_obj.valid() && !memory_obj.is<sol::nil_t>()) {
        if (!memory_obj.is<sol::table>()) {
            throw sol::error("cgltf.options.memory must be a table");
        }
        sol::table memory = memory_obj.as<sol::table>();
        sol::object alloc_obj = memory["alloc"];
        sol::object free_obj = memory["free"];
        sol::object user_data = memory["user-data"];
        bool alloc_present = alloc_obj.valid() && !alloc_obj.is<sol::nil_t>();
        bool free_present = free_obj.valid() && !free_obj.is<sol::nil_t>();
        if (alloc_present || free_present) {
            if (!alloc_obj.is<sol::function>() || !free_obj.is<sol::function>()) {
                throw sol::error("cgltf.options.memory.alloc and free must be functions");
            }
            parsed.context.memory_alloc = alloc_obj.as<sol::function>();
            parsed.context.memory_free = free_obj.as<sol::function>();
            parsed.context.memory_user_data = user_data.valid() ? user_data : sol::make_object(lua, sol::lua_nil);
            parsed.options.memory.alloc_func = cgltf_lua_memory_alloc;
            parsed.options.memory.free_func = cgltf_lua_memory_free;
            parsed.options.memory.user_data = &parsed.context;
        }
    }

    sol::object file_obj = options["file"];
    if (file_obj.valid() && !file_obj.is<sol::nil_t>()) {
        if (!file_obj.is<sol::table>()) {
            throw sol::error("cgltf.options.file must be a table");
        }
        sol::table file = file_obj.as<sol::table>();
        sol::object read_obj = file["read"];
        sol::object release_obj = file["release"];
        sol::object user_data = file["user-data"];
        bool read_present = read_obj.valid() && !read_obj.is<sol::nil_t>();
        bool release_present = release_obj.valid() && !release_obj.is<sol::nil_t>();
        if (read_present || release_present) {
            if (!read_obj.is<sol::function>() || !release_obj.is<sol::function>()) {
                throw sol::error("cgltf.options.file.read and release must be functions");
            }
            parsed.context.file_read = read_obj.as<sol::function>();
            parsed.context.file_release = release_obj.as<sol::function>();
            parsed.context.file_user_data = user_data.valid() ? user_data : sol::make_object(lua, sol::lua_nil);
            parsed.options.file.read = cgltf_lua_file_read;
            parsed.options.file.release = cgltf_lua_file_release;
            parsed.options.file.user_data = &parsed.context;
        }
    }

    return parsed;
}

cgltf_data* require_data(const CgltfDataHandle& handle)
{
    if (!handle.valid()) {
        throw sol::error("cgltf data handle is closed");
    }
    return handle.get();
}

sol::table make_float_table(sol::state_view lua, const cgltf_float* values, cgltf_size count)
{
    sol::table tbl = lua.create_table(static_cast<int>(count), 0);
    for (cgltf_size i = 0; i < count; ++i) {
        tbl[static_cast<int>(i + 1)] = values[i];
    }
    return tbl;
}

sol::table make_string_table(sol::state_view lua, char** values, cgltf_size count)
{
    sol::table tbl = lua.create_table(static_cast<int>(count), 0);
    for (cgltf_size i = 0; i < count; ++i) {
        if (values && values[i]) {
            tbl[static_cast<int>(i + 1)] = values[i];
        } else {
            tbl[static_cast<int>(i + 1)] = sol::lua_nil;
        }
    }
    return tbl;
}

template <typename T>
sol::optional<cgltf_size> index_of(const T* ptr, const T* base, cgltf_size count)
{
    if (!ptr || !base || count == 0) {
        return sol::nullopt;
    }
    auto offset = ptr - base;
    if (offset < 0 || static_cast<cgltf_size>(offset) >= count) {
        return sol::nullopt;
    }
    return static_cast<cgltf_size>(offset + 1);
}

template <typename T>
void set_index(sol::table& tbl, const char* key, const T* ptr, const T* base, cgltf_size count)
{
    sol::optional<cgltf_size> index = index_of(ptr, base, count);
    if (index) {
        tbl[key] = *index;
    } else {
        tbl[key] = sol::lua_nil;
    }
}

sol::table extras_to_table(sol::state_view lua, const cgltf_extras& extras)
{
    sol::table tbl = lua.create_table();
    tbl["start-offset"] = extras.start_offset;
    tbl["end-offset"] = extras.end_offset;
    return tbl;
}

sol::table extensions_to_table(sol::state_view lua, const cgltf_extension* extensions, cgltf_size count)
{
    sol::table tbl = lua.create_table(static_cast<int>(count), 0);
    for (cgltf_size i = 0; i < count; ++i) {
        sol::table entry = lua.create_table();
        if (extensions[i].name) {
            entry["name"] = extensions[i].name;
        } else {
            entry["name"] = sol::lua_nil;
        }
        if (extensions[i].data) {
            entry["data"] = extensions[i].data;
        } else {
            entry["data"] = sol::lua_nil;
        }
        tbl[static_cast<int>(i + 1)] = entry;
    }
    return tbl;
}

void set_string_field(sol::table& tbl, const char* key, const char* value)
{
    if (value) {
        tbl[key] = value;
    } else {
        tbl[key] = sol::lua_nil;
    }
}

struct CgltfConverter {
    sol::state_view lua;
    const cgltf_data* data;

    sol::table texture_transform_to_table(const cgltf_texture_transform& transform)
    {
        sol::table tbl = lua.create_table();
        tbl["offset"] = make_float_table(lua, transform.offset, 2);
        tbl["rotation"] = transform.rotation;
        tbl["scale"] = make_float_table(lua, transform.scale, 2);
        tbl["has-texcoord"] = static_cast<bool>(transform.has_texcoord);
        tbl["texcoord"] = transform.texcoord;
        return tbl;
    }

    sol::table texture_view_to_table(const cgltf_texture_view& view)
    {
        sol::table tbl = lua.create_table();
        set_index(tbl, "texture", view.texture, data->textures, data->textures_count);
        tbl["texcoord"] = view.texcoord;
        tbl["scale"] = view.scale;
        tbl["has-transform"] = static_cast<bool>(view.has_transform);
        if (view.has_transform) {
            tbl["transform"] = texture_transform_to_table(view.transform);
        } else {
            tbl["transform"] = sol::lua_nil;
        }
        tbl["extras"] = extras_to_table(lua, view.extras);
        tbl["extensions"] = extensions_to_table(lua, view.extensions, view.extensions_count);
        return tbl;
    }

    sol::table attribute_to_table(const cgltf_attribute& attr)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", attr.name);
        tbl["type"] = cgltf_attribute_type_to_string(attr.type);
        tbl["index"] = attr.index;
        set_index(tbl, "accessor", attr.data, data->accessors, data->accessors_count);
        return tbl;
    }

    sol::table attribute_list_to_table(const cgltf_attribute* attrs, cgltf_size count)
    {
        sol::table tbl = lua.create_table(static_cast<int>(count), 0);
        for (cgltf_size i = 0; i < count; ++i) {
            tbl[static_cast<int>(i + 1)] = attribute_to_table(attrs[i]);
        }
        return tbl;
    }

    sol::table meshopt_to_table(const cgltf_meshopt_compression& meshopt)
    {
        sol::table tbl = lua.create_table();
        set_index(tbl, "buffer", meshopt.buffer, data->buffers, data->buffers_count);
        tbl["offset"] = meshopt.offset;
        tbl["size"] = meshopt.size;
        tbl["stride"] = meshopt.stride;
        tbl["count"] = meshopt.count;
        tbl["mode"] = cgltf_meshopt_mode_to_string(meshopt.mode);
        tbl["filter"] = cgltf_meshopt_filter_to_string(meshopt.filter);
        return tbl;
    }

    sol::table buffer_view_to_table(const cgltf_buffer_view& view)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", view.name);
        set_index(tbl, "buffer", view.buffer, data->buffers, data->buffers_count);
        tbl["offset"] = view.offset;
        tbl["size"] = view.size;
        tbl["stride"] = view.stride;
        tbl["type"] = cgltf_buffer_view_type_to_string(view.type);
        tbl["has-data"] = view.data != nullptr;
        tbl["has-meshopt-compression"] = static_cast<bool>(view.has_meshopt_compression);
        if (view.has_meshopt_compression) {
            tbl["meshopt-compression"] = meshopt_to_table(view.meshopt_compression);
        } else {
            tbl["meshopt-compression"] = sol::lua_nil;
        }
        tbl["extras"] = extras_to_table(lua, view.extras);
        tbl["extensions"] = extensions_to_table(lua, view.extensions, view.extensions_count);
        return tbl;
    }

    sol::table accessor_sparse_to_table(const cgltf_accessor_sparse& sparse)
    {
        sol::table tbl = lua.create_table();
        tbl["count"] = sparse.count;
        set_index(tbl, "indices-buffer-view", sparse.indices_buffer_view, data->buffer_views, data->buffer_views_count);
        tbl["indices-byte-offset"] = sparse.indices_byte_offset;
        tbl["indices-component-type"] = cgltf_component_type_to_string(sparse.indices_component_type);
        set_index(tbl, "values-buffer-view", sparse.values_buffer_view, data->buffer_views, data->buffer_views_count);
        tbl["values-byte-offset"] = sparse.values_byte_offset;
        tbl["extras"] = extras_to_table(lua, sparse.extras);
        tbl["indices-extras"] = extras_to_table(lua, sparse.indices_extras);
        tbl["values-extras"] = extras_to_table(lua, sparse.values_extras);
        tbl["extensions"] = extensions_to_table(lua, sparse.extensions, sparse.extensions_count);
        tbl["indices-extensions"] = extensions_to_table(lua, sparse.indices_extensions, sparse.indices_extensions_count);
        tbl["values-extensions"] = extensions_to_table(lua, sparse.values_extensions, sparse.values_extensions_count);
        return tbl;
    }

    sol::table accessor_to_table(const cgltf_accessor& accessor)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", accessor.name);
        tbl["component-type"] = cgltf_component_type_to_string(accessor.component_type);
        tbl["normalized"] = static_cast<bool>(accessor.normalized);
        tbl["type"] = cgltf_type_to_string(accessor.type);
        tbl["offset"] = accessor.offset;
        tbl["count"] = accessor.count;
        tbl["stride"] = accessor.stride;
        set_index(tbl, "buffer-view", accessor.buffer_view, data->buffer_views, data->buffer_views_count);
        tbl["has-min"] = static_cast<bool>(accessor.has_min);
        tbl["has-max"] = static_cast<bool>(accessor.has_max);
        if (accessor.has_min) {
            tbl["min"] = make_float_table(lua, accessor.min, 16);
        } else {
            tbl["min"] = sol::lua_nil;
        }
        if (accessor.has_max) {
            tbl["max"] = make_float_table(lua, accessor.max, 16);
        } else {
            tbl["max"] = sol::lua_nil;
        }
        tbl["is-sparse"] = static_cast<bool>(accessor.is_sparse);
        if (accessor.is_sparse) {
            tbl["sparse"] = accessor_sparse_to_table(accessor.sparse);
        } else {
            tbl["sparse"] = sol::lua_nil;
        }
        tbl["extras"] = extras_to_table(lua, accessor.extras);
        tbl["extensions"] = extensions_to_table(lua, accessor.extensions, accessor.extensions_count);
        return tbl;
    }

    sol::table image_to_table(const cgltf_image& image)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", image.name);
        set_string_field(tbl, "uri", image.uri);
        set_index(tbl, "buffer-view", image.buffer_view, data->buffer_views, data->buffer_views_count);
        set_string_field(tbl, "mime-type", image.mime_type);
        tbl["extras"] = extras_to_table(lua, image.extras);
        tbl["extensions"] = extensions_to_table(lua, image.extensions, image.extensions_count);
        return tbl;
    }

    sol::table sampler_to_table(const cgltf_sampler& sampler)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", sampler.name);
        tbl["mag-filter"] = sampler.mag_filter;
        tbl["min-filter"] = sampler.min_filter;
        tbl["wrap-s"] = sampler.wrap_s;
        tbl["wrap-t"] = sampler.wrap_t;
        tbl["extras"] = extras_to_table(lua, sampler.extras);
        tbl["extensions"] = extensions_to_table(lua, sampler.extensions, sampler.extensions_count);
        return tbl;
    }

    sol::table texture_to_table(const cgltf_texture& texture)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", texture.name);
        set_index(tbl, "image", texture.image, data->images, data->images_count);
        set_index(tbl, "sampler", texture.sampler, data->samplers, data->samplers_count);
        tbl["has-basisu"] = static_cast<bool>(texture.has_basisu);
        if (texture.has_basisu) {
            set_index(tbl, "basisu-image", texture.basisu_image, data->images, data->images_count);
        } else {
            tbl["basisu-image"] = sol::lua_nil;
        }
        tbl["extras"] = extras_to_table(lua, texture.extras);
        tbl["extensions"] = extensions_to_table(lua, texture.extensions, texture.extensions_count);
        return tbl;
    }

    sol::table pbr_metallic_roughness_to_table(const cgltf_pbr_metallic_roughness& pbr)
    {
        sol::table tbl = lua.create_table();
        tbl["base-color-texture"] = texture_view_to_table(pbr.base_color_texture);
        tbl["metallic-roughness-texture"] = texture_view_to_table(pbr.metallic_roughness_texture);
        tbl["base-color-factor"] = make_float_table(lua, pbr.base_color_factor, 4);
        tbl["metallic-factor"] = pbr.metallic_factor;
        tbl["roughness-factor"] = pbr.roughness_factor;
        tbl["extras"] = extras_to_table(lua, pbr.extras);
        return tbl;
    }

    sol::table pbr_specular_glossiness_to_table(const cgltf_pbr_specular_glossiness& pbr)
    {
        sol::table tbl = lua.create_table();
        tbl["diffuse-texture"] = texture_view_to_table(pbr.diffuse_texture);
        tbl["specular-glossiness-texture"] = texture_view_to_table(pbr.specular_glossiness_texture);
        tbl["diffuse-factor"] = make_float_table(lua, pbr.diffuse_factor, 4);
        tbl["specular-factor"] = make_float_table(lua, pbr.specular_factor, 3);
        tbl["glossiness-factor"] = pbr.glossiness_factor;
        return tbl;
    }

    sol::table clearcoat_to_table(const cgltf_clearcoat& clearcoat)
    {
        sol::table tbl = lua.create_table();
        tbl["clearcoat-texture"] = texture_view_to_table(clearcoat.clearcoat_texture);
        tbl["clearcoat-roughness-texture"] = texture_view_to_table(clearcoat.clearcoat_roughness_texture);
        tbl["clearcoat-normal-texture"] = texture_view_to_table(clearcoat.clearcoat_normal_texture);
        tbl["clearcoat-factor"] = clearcoat.clearcoat_factor;
        tbl["clearcoat-roughness-factor"] = clearcoat.clearcoat_roughness_factor;
        return tbl;
    }

    sol::table transmission_to_table(const cgltf_transmission& transmission)
    {
        sol::table tbl = lua.create_table();
        tbl["transmission-texture"] = texture_view_to_table(transmission.transmission_texture);
        tbl["transmission-factor"] = transmission.transmission_factor;
        return tbl;
    }

    sol::table ior_to_table(const cgltf_ior& ior)
    {
        sol::table tbl = lua.create_table();
        tbl["ior"] = ior.ior;
        return tbl;
    }

    sol::table specular_to_table(const cgltf_specular& specular)
    {
        sol::table tbl = lua.create_table();
        tbl["specular-texture"] = texture_view_to_table(specular.specular_texture);
        tbl["specular-color-texture"] = texture_view_to_table(specular.specular_color_texture);
        tbl["specular-color-factor"] = make_float_table(lua, specular.specular_color_factor, 3);
        tbl["specular-factor"] = specular.specular_factor;
        return tbl;
    }

    sol::table volume_to_table(const cgltf_volume& volume)
    {
        sol::table tbl = lua.create_table();
        tbl["thickness-texture"] = texture_view_to_table(volume.thickness_texture);
        tbl["thickness-factor"] = volume.thickness_factor;
        tbl["attenuation-color"] = make_float_table(lua, volume.attenuation_color, 3);
        tbl["attenuation-distance"] = volume.attenuation_distance;
        return tbl;
    }

    sol::table sheen_to_table(const cgltf_sheen& sheen)
    {
        sol::table tbl = lua.create_table();
        tbl["sheen-color-texture"] = texture_view_to_table(sheen.sheen_color_texture);
        tbl["sheen-color-factor"] = make_float_table(lua, sheen.sheen_color_factor, 3);
        tbl["sheen-roughness-texture"] = texture_view_to_table(sheen.sheen_roughness_texture);
        tbl["sheen-roughness-factor"] = sheen.sheen_roughness_factor;
        return tbl;
    }

    sol::table emissive_strength_to_table(const cgltf_emissive_strength& strength)
    {
        sol::table tbl = lua.create_table();
        tbl["emissive-strength"] = strength.emissive_strength;
        return tbl;
    }

    sol::table iridescence_to_table(const cgltf_iridescence& iridescence)
    {
        sol::table tbl = lua.create_table();
        tbl["iridescence-factor"] = iridescence.iridescence_factor;
        tbl["iridescence-texture"] = texture_view_to_table(iridescence.iridescence_texture);
        tbl["iridescence-ior"] = iridescence.iridescence_ior;
        tbl["iridescence-thickness-min"] = iridescence.iridescence_thickness_min;
        tbl["iridescence-thickness-max"] = iridescence.iridescence_thickness_max;
        tbl["iridescence-thickness-texture"] = texture_view_to_table(iridescence.iridescence_thickness_texture);
        return tbl;
    }

    sol::table material_to_table(const cgltf_material& material)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", material.name);
        tbl["has-pbr-metallic-roughness"] = static_cast<bool>(material.has_pbr_metallic_roughness);
        tbl["has-pbr-specular-glossiness"] = static_cast<bool>(material.has_pbr_specular_glossiness);
        tbl["has-clearcoat"] = static_cast<bool>(material.has_clearcoat);
        tbl["has-transmission"] = static_cast<bool>(material.has_transmission);
        tbl["has-volume"] = static_cast<bool>(material.has_volume);
        tbl["has-ior"] = static_cast<bool>(material.has_ior);
        tbl["has-specular"] = static_cast<bool>(material.has_specular);
        tbl["has-sheen"] = static_cast<bool>(material.has_sheen);
        tbl["has-emissive-strength"] = static_cast<bool>(material.has_emissive_strength);
        tbl["has-iridescence"] = static_cast<bool>(material.has_iridescence);
        tbl["pbr-metallic-roughness"] = pbr_metallic_roughness_to_table(material.pbr_metallic_roughness);
        tbl["pbr-specular-glossiness"] = pbr_specular_glossiness_to_table(material.pbr_specular_glossiness);
        tbl["clearcoat"] = clearcoat_to_table(material.clearcoat);
        tbl["ior"] = ior_to_table(material.ior);
        tbl["specular"] = specular_to_table(material.specular);
        tbl["sheen"] = sheen_to_table(material.sheen);
        tbl["transmission"] = transmission_to_table(material.transmission);
        tbl["volume"] = volume_to_table(material.volume);
        tbl["emissive-strength"] = emissive_strength_to_table(material.emissive_strength);
        tbl["iridescence"] = iridescence_to_table(material.iridescence);
        tbl["normal-texture"] = texture_view_to_table(material.normal_texture);
        tbl["occlusion-texture"] = texture_view_to_table(material.occlusion_texture);
        tbl["emissive-texture"] = texture_view_to_table(material.emissive_texture);
        tbl["emissive-factor"] = make_float_table(lua, material.emissive_factor, 3);
        tbl["alpha-mode"] = cgltf_alpha_mode_to_string(material.alpha_mode);
        tbl["alpha-cutoff"] = material.alpha_cutoff;
        tbl["double-sided"] = static_cast<bool>(material.double_sided);
        tbl["unlit"] = static_cast<bool>(material.unlit);
        tbl["extras"] = extras_to_table(lua, material.extras);
        tbl["extensions"] = extensions_to_table(lua, material.extensions, material.extensions_count);
        return tbl;
    }

    sol::table material_mapping_to_table(const cgltf_material_mapping& mapping)
    {
        sol::table tbl = lua.create_table();
        tbl["variant"] = mapping.variant;
        set_index(tbl, "material", mapping.material, data->materials, data->materials_count);
        tbl["extras"] = extras_to_table(lua, mapping.extras);
        return tbl;
    }

    sol::table morph_target_to_table(const cgltf_morph_target& target)
    {
        sol::table tbl = lua.create_table();
        tbl["attributes"] = attribute_list_to_table(target.attributes, target.attributes_count);
        return tbl;
    }

    sol::table draco_to_table(const cgltf_draco_mesh_compression& draco)
    {
        sol::table tbl = lua.create_table();
        set_index(tbl, "buffer-view", draco.buffer_view, data->buffer_views, data->buffer_views_count);
        tbl["attributes"] = attribute_list_to_table(draco.attributes, draco.attributes_count);
        return tbl;
    }

    sol::table instancing_to_table(const cgltf_mesh_gpu_instancing& instancing)
    {
        sol::table tbl = lua.create_table();
        set_index(tbl, "buffer-view", instancing.buffer_view, data->buffer_views, data->buffer_views_count);
        tbl["attributes"] = attribute_list_to_table(instancing.attributes, instancing.attributes_count);
        return tbl;
    }

    sol::table primitive_to_table(const cgltf_primitive& prim)
    {
        sol::table tbl = lua.create_table();
        tbl["type"] = cgltf_primitive_type_to_string(prim.type);
        set_index(tbl, "indices", prim.indices, data->accessors, data->accessors_count);
        set_index(tbl, "material", prim.material, data->materials, data->materials_count);
        tbl["attributes"] = attribute_list_to_table(prim.attributes, prim.attributes_count);
        sol::table targets_tbl = lua.create_table(static_cast<int>(prim.targets_count), 0);
        for (cgltf_size i = 0; i < prim.targets_count; ++i) {
            targets_tbl[static_cast<int>(i + 1)] = morph_target_to_table(prim.targets[i]);
        }
        tbl["targets"] = targets_tbl;
        tbl["extras"] = extras_to_table(lua, prim.extras);
        tbl["has-draco-mesh-compression"] = static_cast<bool>(prim.has_draco_mesh_compression);
        if (prim.has_draco_mesh_compression) {
            tbl["draco-mesh-compression"] = draco_to_table(prim.draco_mesh_compression);
        } else {
            tbl["draco-mesh-compression"] = sol::lua_nil;
        }
        sol::table mappings_tbl = lua.create_table(static_cast<int>(prim.mappings_count), 0);
        for (cgltf_size i = 0; i < prim.mappings_count; ++i) {
            mappings_tbl[static_cast<int>(i + 1)] = material_mapping_to_table(prim.mappings[i]);
        }
        tbl["mappings"] = mappings_tbl;
        tbl["extensions"] = extensions_to_table(lua, prim.extensions, prim.extensions_count);
        return tbl;
    }

    sol::table mesh_to_table(const cgltf_mesh& mesh)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", mesh.name);
        sol::table prims = lua.create_table(static_cast<int>(mesh.primitives_count), 0);
        for (cgltf_size i = 0; i < mesh.primitives_count; ++i) {
            prims[static_cast<int>(i + 1)] = primitive_to_table(mesh.primitives[i]);
        }
        tbl["primitives"] = prims;
        if (mesh.weights && mesh.weights_count > 0) {
            tbl["weights"] = make_float_table(lua, mesh.weights, mesh.weights_count);
        } else {
            tbl["weights"] = lua.create_table();
        }
        tbl["target-names"] = make_string_table(lua, mesh.target_names, mesh.target_names_count);
        tbl["extras"] = extras_to_table(lua, mesh.extras);
        tbl["extensions"] = extensions_to_table(lua, mesh.extensions, mesh.extensions_count);
        return tbl;
    }

    sol::table skin_to_table(const cgltf_skin& skin)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", skin.name);
        sol::table joints_tbl = lua.create_table(static_cast<int>(skin.joints_count), 0);
        for (cgltf_size i = 0; i < skin.joints_count; ++i) {
            sol::optional<cgltf_size> idx = index_of(skin.joints[i], data->nodes, data->nodes_count);
            joints_tbl[static_cast<int>(i + 1)] = idx ? sol::make_object(lua, *idx) : sol::lua_nil;
        }
        tbl["joints"] = joints_tbl;
        set_index(tbl, "skeleton", skin.skeleton, data->nodes, data->nodes_count);
        set_index(tbl, "inverse-bind-matrices", skin.inverse_bind_matrices, data->accessors, data->accessors_count);
        tbl["extras"] = extras_to_table(lua, skin.extras);
        tbl["extensions"] = extensions_to_table(lua, skin.extensions, skin.extensions_count);
        return tbl;
    }

    sol::table camera_to_table(const cgltf_camera& camera)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", camera.name);
        tbl["type"] = cgltf_camera_type_to_string(camera.type);
        if (camera.type == cgltf_camera_type_perspective) {
            sol::table persp = lua.create_table();
            persp["has-aspect-ratio"] = static_cast<bool>(camera.data.perspective.has_aspect_ratio);
            persp["aspect-ratio"] = camera.data.perspective.aspect_ratio;
            persp["yfov"] = camera.data.perspective.yfov;
            persp["has-zfar"] = static_cast<bool>(camera.data.perspective.has_zfar);
            persp["zfar"] = camera.data.perspective.zfar;
            persp["znear"] = camera.data.perspective.znear;
            persp["extras"] = extras_to_table(lua, camera.data.perspective.extras);
            tbl["perspective"] = persp;
            tbl["orthographic"] = sol::lua_nil;
        } else if (camera.type == cgltf_camera_type_orthographic) {
            sol::table ortho = lua.create_table();
            ortho["xmag"] = camera.data.orthographic.xmag;
            ortho["ymag"] = camera.data.orthographic.ymag;
            ortho["zfar"] = camera.data.orthographic.zfar;
            ortho["znear"] = camera.data.orthographic.znear;
            ortho["extras"] = extras_to_table(lua, camera.data.orthographic.extras);
            tbl["orthographic"] = ortho;
            tbl["perspective"] = sol::lua_nil;
        } else {
            tbl["perspective"] = sol::lua_nil;
            tbl["orthographic"] = sol::lua_nil;
        }
        tbl["extras"] = extras_to_table(lua, camera.extras);
        tbl["extensions"] = extensions_to_table(lua, camera.extensions, camera.extensions_count);
        return tbl;
    }

    sol::table light_to_table(const cgltf_light& light)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", light.name);
        tbl["color"] = make_float_table(lua, light.color, 3);
        tbl["intensity"] = light.intensity;
        tbl["type"] = cgltf_light_type_to_string(light.type);
        tbl["range"] = light.range;
        tbl["spot-inner-cone-angle"] = light.spot_inner_cone_angle;
        tbl["spot-outer-cone-angle"] = light.spot_outer_cone_angle;
        tbl["extras"] = extras_to_table(lua, light.extras);
        return tbl;
    }

    sol::table node_to_table(const cgltf_node& node)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", node.name);
        set_index(tbl, "parent", node.parent, data->nodes, data->nodes_count);
        sol::table children_tbl = lua.create_table(static_cast<int>(node.children_count), 0);
        for (cgltf_size i = 0; i < node.children_count; ++i) {
            sol::optional<cgltf_size> idx = index_of(node.children[i], data->nodes, data->nodes_count);
            children_tbl[static_cast<int>(i + 1)] = idx ? sol::make_object(lua, *idx) : sol::lua_nil;
        }
        tbl["children"] = children_tbl;
        set_index(tbl, "skin", node.skin, data->skins, data->skins_count);
        set_index(tbl, "mesh", node.mesh, data->meshes, data->meshes_count);
        set_index(tbl, "camera", node.camera, data->cameras, data->cameras_count);
        set_index(tbl, "light", node.light, data->lights, data->lights_count);
        if (node.weights && node.weights_count > 0) {
            tbl["weights"] = make_float_table(lua, node.weights, node.weights_count);
        } else {
            tbl["weights"] = lua.create_table();
        }
        tbl["has-translation"] = static_cast<bool>(node.has_translation);
        tbl["has-rotation"] = static_cast<bool>(node.has_rotation);
        tbl["has-scale"] = static_cast<bool>(node.has_scale);
        tbl["has-matrix"] = static_cast<bool>(node.has_matrix);
        tbl["translation"] = make_float_table(lua, node.translation, 3);
        tbl["rotation"] = make_float_table(lua, node.rotation, 4);
        tbl["scale"] = make_float_table(lua, node.scale, 3);
        tbl["matrix"] = make_float_table(lua, node.matrix, 16);
        tbl["extras"] = extras_to_table(lua, node.extras);
        tbl["has-mesh-gpu-instancing"] = static_cast<bool>(node.has_mesh_gpu_instancing);
        if (node.has_mesh_gpu_instancing) {
            tbl["mesh-gpu-instancing"] = instancing_to_table(node.mesh_gpu_instancing);
        } else {
            tbl["mesh-gpu-instancing"] = sol::lua_nil;
        }
        tbl["extensions"] = extensions_to_table(lua, node.extensions, node.extensions_count);
        return tbl;
    }

    sol::table scene_to_table(const cgltf_scene& scene)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", scene.name);
        sol::table nodes_tbl = lua.create_table(static_cast<int>(scene.nodes_count), 0);
        for (cgltf_size i = 0; i < scene.nodes_count; ++i) {
            sol::optional<cgltf_size> idx = index_of(scene.nodes[i], data->nodes, data->nodes_count);
            nodes_tbl[static_cast<int>(i + 1)] = idx ? sol::make_object(lua, *idx) : sol::lua_nil;
        }
        tbl["nodes"] = nodes_tbl;
        tbl["extras"] = extras_to_table(lua, scene.extras);
        tbl["extensions"] = extensions_to_table(lua, scene.extensions, scene.extensions_count);
        return tbl;
    }

    sol::table animation_sampler_to_table(const cgltf_animation_sampler& sampler)
    {
        sol::table tbl = lua.create_table();
        set_index(tbl, "input", sampler.input, data->accessors, data->accessors_count);
        set_index(tbl, "output", sampler.output, data->accessors, data->accessors_count);
        tbl["interpolation"] = cgltf_interpolation_to_string(sampler.interpolation);
        tbl["extras"] = extras_to_table(lua, sampler.extras);
        tbl["extensions"] = extensions_to_table(lua, sampler.extensions, sampler.extensions_count);
        return tbl;
    }

    sol::table animation_channel_to_table(const cgltf_animation_channel& channel,
        const cgltf_animation_sampler* sampler_base, cgltf_size sampler_count)
    {
        sol::table tbl = lua.create_table();
        sol::optional<cgltf_size> sampler_index = index_of(channel.sampler, sampler_base, sampler_count);
        if (sampler_index) {
            tbl["sampler"] = *sampler_index;
        } else {
            tbl["sampler"] = sol::lua_nil;
        }
        set_index(tbl, "target-node", channel.target_node, data->nodes, data->nodes_count);
        tbl["target-path"] = cgltf_animation_path_to_string(channel.target_path);
        tbl["extras"] = extras_to_table(lua, channel.extras);
        tbl["extensions"] = extensions_to_table(lua, channel.extensions, channel.extensions_count);
        return tbl;
    }

    sol::table animation_to_table(const cgltf_animation& animation)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", animation.name);
        sol::table samplers_tbl = lua.create_table(static_cast<int>(animation.samplers_count), 0);
        for (cgltf_size i = 0; i < animation.samplers_count; ++i) {
            samplers_tbl[static_cast<int>(i + 1)] = animation_sampler_to_table(animation.samplers[i]);
        }
        tbl["samplers"] = samplers_tbl;
        sol::table channels_tbl = lua.create_table(static_cast<int>(animation.channels_count), 0);
        for (cgltf_size i = 0; i < animation.channels_count; ++i) {
            channels_tbl[static_cast<int>(i + 1)] = animation_channel_to_table(animation.channels[i],
                animation.samplers, animation.samplers_count);
        }
        tbl["channels"] = channels_tbl;
        tbl["extras"] = extras_to_table(lua, animation.extras);
        tbl["extensions"] = extensions_to_table(lua, animation.extensions, animation.extensions_count);
        return tbl;
    }

    sol::table variant_to_table(const cgltf_material_variant& variant)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "name", variant.name);
        tbl["extras"] = extras_to_table(lua, variant.extras);
        return tbl;
    }

    sol::table asset_to_table(const cgltf_asset& asset)
    {
        sol::table tbl = lua.create_table();
        set_string_field(tbl, "copyright", asset.copyright);
        set_string_field(tbl, "generator", asset.generator);
        set_string_field(tbl, "version", asset.version);
        set_string_field(tbl, "min-version", asset.min_version);
        tbl["extras"] = extras_to_table(lua, asset.extras);
        tbl["extensions"] = extensions_to_table(lua, asset.extensions, asset.extensions_count);
        return tbl;
    }

    sol::table data_to_table()
    {
        sol::table tbl = lua.create_table();
        tbl["file-type"] = cgltf_file_type_to_string(data->file_type);
        tbl["asset"] = asset_to_table(data->asset);
        sol::table meshes_tbl = lua.create_table(static_cast<int>(data->meshes_count), 0);
        for (cgltf_size i = 0; i < data->meshes_count; ++i) {
            meshes_tbl[static_cast<int>(i + 1)] = mesh_to_table(data->meshes[i]);
        }
        tbl["meshes"] = meshes_tbl;
        sol::table materials_tbl = lua.create_table(static_cast<int>(data->materials_count), 0);
        for (cgltf_size i = 0; i < data->materials_count; ++i) {
            materials_tbl[static_cast<int>(i + 1)] = material_to_table(data->materials[i]);
        }
        tbl["materials"] = materials_tbl;
        sol::table accessors_tbl = lua.create_table(static_cast<int>(data->accessors_count), 0);
        for (cgltf_size i = 0; i < data->accessors_count; ++i) {
            accessors_tbl[static_cast<int>(i + 1)] = accessor_to_table(data->accessors[i]);
        }
        tbl["accessors"] = accessors_tbl;
        sol::table views_tbl = lua.create_table(static_cast<int>(data->buffer_views_count), 0);
        for (cgltf_size i = 0; i < data->buffer_views_count; ++i) {
            views_tbl[static_cast<int>(i + 1)] = buffer_view_to_table(data->buffer_views[i]);
        }
        tbl["buffer-views"] = views_tbl;
        sol::table buffers_tbl = lua.create_table(static_cast<int>(data->buffers_count), 0);
        for (cgltf_size i = 0; i < data->buffers_count; ++i) {
            sol::table entry = lua.create_table();
            const cgltf_buffer& buffer = data->buffers[i];
            set_string_field(entry, "name", buffer.name);
            entry["size"] = buffer.size;
            set_string_field(entry, "uri", buffer.uri);
            entry["has-data"] = buffer.data != nullptr;
            entry["data-free-method"] = cgltf_data_free_method_to_string(buffer.data_free_method);
            entry["extras"] = extras_to_table(lua, buffer.extras);
            entry["extensions"] = extensions_to_table(lua, buffer.extensions, buffer.extensions_count);
            buffers_tbl[static_cast<int>(i + 1)] = entry;
        }
        tbl["buffers"] = buffers_tbl;
        sol::table images_tbl = lua.create_table(static_cast<int>(data->images_count), 0);
        for (cgltf_size i = 0; i < data->images_count; ++i) {
            images_tbl[static_cast<int>(i + 1)] = image_to_table(data->images[i]);
        }
        tbl["images"] = images_tbl;
        sol::table textures_tbl = lua.create_table(static_cast<int>(data->textures_count), 0);
        for (cgltf_size i = 0; i < data->textures_count; ++i) {
            textures_tbl[static_cast<int>(i + 1)] = texture_to_table(data->textures[i]);
        }
        tbl["textures"] = textures_tbl;
        sol::table samplers_tbl = lua.create_table(static_cast<int>(data->samplers_count), 0);
        for (cgltf_size i = 0; i < data->samplers_count; ++i) {
            samplers_tbl[static_cast<int>(i + 1)] = sampler_to_table(data->samplers[i]);
        }
        tbl["samplers"] = samplers_tbl;
        sol::table skins_tbl = lua.create_table(static_cast<int>(data->skins_count), 0);
        for (cgltf_size i = 0; i < data->skins_count; ++i) {
            skins_tbl[static_cast<int>(i + 1)] = skin_to_table(data->skins[i]);
        }
        tbl["skins"] = skins_tbl;
        sol::table cameras_tbl = lua.create_table(static_cast<int>(data->cameras_count), 0);
        for (cgltf_size i = 0; i < data->cameras_count; ++i) {
            cameras_tbl[static_cast<int>(i + 1)] = camera_to_table(data->cameras[i]);
        }
        tbl["cameras"] = cameras_tbl;
        sol::table lights_tbl = lua.create_table(static_cast<int>(data->lights_count), 0);
        for (cgltf_size i = 0; i < data->lights_count; ++i) {
            lights_tbl[static_cast<int>(i + 1)] = light_to_table(data->lights[i]);
        }
        tbl["lights"] = lights_tbl;
        sol::table nodes_tbl = lua.create_table(static_cast<int>(data->nodes_count), 0);
        for (cgltf_size i = 0; i < data->nodes_count; ++i) {
            nodes_tbl[static_cast<int>(i + 1)] = node_to_table(data->nodes[i]);
        }
        tbl["nodes"] = nodes_tbl;
        sol::table scenes_tbl = lua.create_table(static_cast<int>(data->scenes_count), 0);
        for (cgltf_size i = 0; i < data->scenes_count; ++i) {
            scenes_tbl[static_cast<int>(i + 1)] = scene_to_table(data->scenes[i]);
        }
        tbl["scenes"] = scenes_tbl;
        set_index(tbl, "scene", data->scene, data->scenes, data->scenes_count);
        sol::table animations_tbl = lua.create_table(static_cast<int>(data->animations_count), 0);
        for (cgltf_size i = 0; i < data->animations_count; ++i) {
            animations_tbl[static_cast<int>(i + 1)] = animation_to_table(data->animations[i]);
        }
        tbl["animations"] = animations_tbl;
        sol::table variants_tbl = lua.create_table(static_cast<int>(data->variants_count), 0);
        for (cgltf_size i = 0; i < data->variants_count; ++i) {
            variants_tbl[static_cast<int>(i + 1)] = variant_to_table(data->variants[i]);
        }
        tbl["variants"] = variants_tbl;
        tbl["extras"] = extras_to_table(lua, data->extras);
        tbl["data-extensions"] = extensions_to_table(lua, data->data_extensions, data->data_extensions_count);
        tbl["extensions-used"] = make_string_table(lua, data->extensions_used, data->extensions_used_count);
        tbl["extensions-required"] = make_string_table(lua, data->extensions_required, data->extensions_required_count);
        tbl["json-size"] = data->json_size;
        tbl["bin-size"] = data->bin_size;
        return tbl;
    }
};

CgltfDataHandle cgltf_parse_data(sol::state_view lua, const sol::object& options_obj, const std::string& data)
{
    ParsedCgltfOptions parsed = parse_cgltf_options(lua, options_obj);
    cgltf_data* out_data = nullptr;
    cgltf_result result = cgltf_parse(&parsed.options, data.data(), data.size(), &out_data);
    if (result != cgltf_result_success) {
        std::string message = "cgltf.parse failed: ";
        message += cgltf_result_to_string(result);
        if (!parsed.context.last_error.empty()) {
            message += " (" + parsed.context.last_error + ")";
        }
        throw sol::error(message);
    }
    return CgltfDataHandle(out_data);
}

CgltfDataHandle cgltf_parse_file(sol::state_view lua, const sol::object& options_obj, const std::string& path)
{
    ParsedCgltfOptions parsed = parse_cgltf_options(lua, options_obj);
    cgltf_data* out_data = nullptr;
    cgltf_result result = cgltf_parse_file(&parsed.options, path.c_str(), &out_data);
    if (result != cgltf_result_success) {
        std::string message = "cgltf.parse-file failed: ";
        message += cgltf_result_to_string(result);
        if (!parsed.context.last_error.empty()) {
            message += " (" + parsed.context.last_error + ")";
        }
        throw sol::error(message);
    }
    return CgltfDataHandle(out_data);
}

sol::table cgltf_accessor_read_float_table(sol::state_view lua, const cgltf_accessor* accessor, cgltf_size index,
    cgltf_size element_size)
{
    std::vector<cgltf_float> out(element_size, 0.0f);
    if (!cgltf_accessor_read_float(accessor, index, out.data(), element_size)) {
        return lua.create_table();
    }
    sol::table tbl = lua.create_table(static_cast<int>(element_size), 0);
    for (cgltf_size i = 0; i < element_size; ++i) {
        tbl[static_cast<int>(i + 1)] = out[i];
    }
    return tbl;
}

sol::table cgltf_accessor_read_uint_table(sol::state_view lua, const cgltf_accessor* accessor, cgltf_size index,
    cgltf_size element_size)
{
    std::vector<cgltf_uint> out(element_size, 0);
    if (!cgltf_accessor_read_uint(accessor, index, out.data(), element_size)) {
        return lua.create_table();
    }
    sol::table tbl = lua.create_table(static_cast<int>(element_size), 0);
    for (cgltf_size i = 0; i < element_size; ++i) {
        tbl[static_cast<int>(i + 1)] = out[i];
    }
    return tbl;
}

cgltf_size clamp_index(cgltf_size index, cgltf_size count, const char* label)
{
    if (index == 0 || index > count) {
        throw sol::error(std::string(label) + " index out of range");
    }
    return index - 1;
}

std::string decode_string(const std::string& input)
{
    std::vector<char> buffer(input.begin(), input.end());
    buffer.push_back('\0');
    cgltf_size out_size = cgltf_decode_string(buffer.data());
    return std::string(buffer.data(), static_cast<size_t>(out_size));
}

std::string decode_uri(const std::string& input)
{
    std::vector<char> buffer(input.begin(), input.end());
    buffer.push_back('\0');
    cgltf_size out_size = cgltf_decode_uri(buffer.data());
    return std::string(buffer.data(), static_cast<size_t>(out_size));
}

sol::table cgltf_enums(sol::state_view lua)
{
    sol::table enums = lua.create_table();
    sol::table results = lua.create_table();
    results["success"] = cgltf_result_success;
    results["data-too-short"] = cgltf_result_data_too_short;
    results["unknown-format"] = cgltf_result_unknown_format;
    results["invalid-json"] = cgltf_result_invalid_json;
    results["invalid-gltf"] = cgltf_result_invalid_gltf;
    results["invalid-options"] = cgltf_result_invalid_options;
    results["file-not-found"] = cgltf_result_file_not_found;
    results["io-error"] = cgltf_result_io_error;
    results["out-of-memory"] = cgltf_result_out_of_memory;
    results["legacy-gltf"] = cgltf_result_legacy_gltf;
    enums["result"] = results;

    sol::table file_types = lua.create_table();
    file_types["auto"] = cgltf_file_type_invalid;
    file_types["gltf"] = cgltf_file_type_gltf;
    file_types["glb"] = cgltf_file_type_glb;
    enums["file-type"] = file_types;

    sol::table buffer_view_types = lua.create_table();
    buffer_view_types["invalid"] = cgltf_buffer_view_type_invalid;
    buffer_view_types["indices"] = cgltf_buffer_view_type_indices;
    buffer_view_types["vertices"] = cgltf_buffer_view_type_vertices;
    enums["buffer-view-type"] = buffer_view_types;

    sol::table attribute_types = lua.create_table();
    attribute_types["invalid"] = cgltf_attribute_type_invalid;
    attribute_types["position"] = cgltf_attribute_type_position;
    attribute_types["normal"] = cgltf_attribute_type_normal;
    attribute_types["tangent"] = cgltf_attribute_type_tangent;
    attribute_types["texcoord"] = cgltf_attribute_type_texcoord;
    attribute_types["color"] = cgltf_attribute_type_color;
    attribute_types["joints"] = cgltf_attribute_type_joints;
    attribute_types["weights"] = cgltf_attribute_type_weights;
    attribute_types["custom"] = cgltf_attribute_type_custom;
    enums["attribute-type"] = attribute_types;

    sol::table component_types = lua.create_table();
    component_types["invalid"] = cgltf_component_type_invalid;
    component_types["r-8"] = cgltf_component_type_r_8;
    component_types["r-8u"] = cgltf_component_type_r_8u;
    component_types["r-16"] = cgltf_component_type_r_16;
    component_types["r-16u"] = cgltf_component_type_r_16u;
    component_types["r-32u"] = cgltf_component_type_r_32u;
    component_types["r-32f"] = cgltf_component_type_r_32f;
    enums["component-type"] = component_types;

    sol::table types = lua.create_table();
    types["invalid"] = cgltf_type_invalid;
    types["scalar"] = cgltf_type_scalar;
    types["vec2"] = cgltf_type_vec2;
    types["vec3"] = cgltf_type_vec3;
    types["vec4"] = cgltf_type_vec4;
    types["mat2"] = cgltf_type_mat2;
    types["mat3"] = cgltf_type_mat3;
    types["mat4"] = cgltf_type_mat4;
    enums["type"] = types;

    sol::table primitive_types = lua.create_table();
    primitive_types["points"] = cgltf_primitive_type_points;
    primitive_types["lines"] = cgltf_primitive_type_lines;
    primitive_types["line-loop"] = cgltf_primitive_type_line_loop;
    primitive_types["line-strip"] = cgltf_primitive_type_line_strip;
    primitive_types["triangles"] = cgltf_primitive_type_triangles;
    primitive_types["triangle-strip"] = cgltf_primitive_type_triangle_strip;
    primitive_types["triangle-fan"] = cgltf_primitive_type_triangle_fan;
    enums["primitive-type"] = primitive_types;

    sol::table alpha_modes = lua.create_table();
    alpha_modes["opaque"] = cgltf_alpha_mode_opaque;
    alpha_modes["mask"] = cgltf_alpha_mode_mask;
    alpha_modes["blend"] = cgltf_alpha_mode_blend;
    enums["alpha-mode"] = alpha_modes;

    sol::table animation_paths = lua.create_table();
    animation_paths["invalid"] = cgltf_animation_path_type_invalid;
    animation_paths["translation"] = cgltf_animation_path_type_translation;
    animation_paths["rotation"] = cgltf_animation_path_type_rotation;
    animation_paths["scale"] = cgltf_animation_path_type_scale;
    animation_paths["weights"] = cgltf_animation_path_type_weights;
    enums["animation-path"] = animation_paths;

    sol::table interpolation = lua.create_table();
    interpolation["linear"] = cgltf_interpolation_type_linear;
    interpolation["step"] = cgltf_interpolation_type_step;
    interpolation["cubic-spline"] = cgltf_interpolation_type_cubic_spline;
    enums["interpolation"] = interpolation;

    sol::table camera_types = lua.create_table();
    camera_types["invalid"] = cgltf_camera_type_invalid;
    camera_types["perspective"] = cgltf_camera_type_perspective;
    camera_types["orthographic"] = cgltf_camera_type_orthographic;
    enums["camera-type"] = camera_types;

    sol::table light_types = lua.create_table();
    light_types["invalid"] = cgltf_light_type_invalid;
    light_types["directional"] = cgltf_light_type_directional;
    light_types["point"] = cgltf_light_type_point;
    light_types["spot"] = cgltf_light_type_spot;
    enums["light-type"] = light_types;

    sol::table data_free_methods = lua.create_table();
    data_free_methods["none"] = cgltf_data_free_method_none;
    data_free_methods["file-release"] = cgltf_data_free_method_file_release;
    data_free_methods["memory-free"] = cgltf_data_free_method_memory_free;
    enums["data-free-method"] = data_free_methods;

    sol::table meshopt_modes = lua.create_table();
    meshopt_modes["invalid"] = cgltf_meshopt_compression_mode_invalid;
    meshopt_modes["attributes"] = cgltf_meshopt_compression_mode_attributes;
    meshopt_modes["triangles"] = cgltf_meshopt_compression_mode_triangles;
    meshopt_modes["indices"] = cgltf_meshopt_compression_mode_indices;
    enums["meshopt-mode"] = meshopt_modes;

    sol::table meshopt_filters = lua.create_table();
    meshopt_filters["none"] = cgltf_meshopt_compression_filter_none;
    meshopt_filters["octahedral"] = cgltf_meshopt_compression_filter_octahedral;
    meshopt_filters["quaternion"] = cgltf_meshopt_compression_filter_quaternion;
    meshopt_filters["exponential"] = cgltf_meshopt_compression_filter_exponential;
    enums["meshopt-filter"] = meshopt_filters;

    return enums;
}

sol::table create_cgltf_table(sol::state_view lua)
{
    sol::table cgltf_table = lua.create_table();

    cgltf_table["enums"] = cgltf_enums(lua);

    cgltf_table.set_function("parse", sol::overload(
        [lua](const std::string& data) {
            return cgltf_parse_data(lua, sol::make_object(lua, sol::lua_nil), data);
        },
        [lua](const sol::object& options, const std::string& data) {
            return cgltf_parse_data(lua, options, data);
        }
    ));

    cgltf_table.set_function("parse-file", sol::overload(
        [lua](const std::string& path) {
            return cgltf_parse_file(lua, sol::make_object(lua, sol::lua_nil), path);
        },
        [lua](const sol::object& options, const std::string& path) {
            return cgltf_parse_file(lua, options, path);
        }
    ));

    cgltf_table.set_function("load-buffer-base64", sol::overload(
        [lua](cgltf_size size, const std::string& base64) {
            ParsedCgltfOptions parsed = parse_cgltf_options(lua, sol::make_object(lua, sol::lua_nil));
            void* out_data = nullptr;
            cgltf_result result = cgltf_load_buffer_base64(&parsed.options, size, base64.c_str(), &out_data);
            if (result != cgltf_result_success) {
                std::string message = "cgltf.load-buffer-base64 failed: ";
                message += cgltf_result_to_string(result);
                if (!parsed.context.last_error.empty()) {
                    message += " (" + parsed.context.last_error + ")";
                }
                throw sol::error(message);
            }
            std::string output(static_cast<const char*>(out_data), static_cast<size_t>(size));
            if (parsed.options.memory.free_func) {
                parsed.options.memory.free_func(parsed.options.memory.user_data, out_data);
            } else {
                std::free(out_data);
            }
            return output;
        },
        [lua](const sol::object& options, cgltf_size size, const std::string& base64) {
            ParsedCgltfOptions parsed = parse_cgltf_options(lua, options);
            void* out_data = nullptr;
            cgltf_result result = cgltf_load_buffer_base64(&parsed.options, size, base64.c_str(), &out_data);
            if (result != cgltf_result_success) {
                std::string message = "cgltf.load-buffer-base64 failed: ";
                message += cgltf_result_to_string(result);
                if (!parsed.context.last_error.empty()) {
                    message += " (" + parsed.context.last_error + ")";
                }
                throw sol::error(message);
            }
            std::string output(static_cast<const char*>(out_data), static_cast<size_t>(size));
            if (parsed.options.memory.free_func) {
                parsed.options.memory.free_func(parsed.options.memory.user_data, out_data);
            } else {
                std::free(out_data);
            }
            return output;
        }
    ));

    cgltf_table.set_function("decode-string", [](const std::string& input) {
        return decode_string(input);
    });

    cgltf_table.set_function("decode-uri", [](const std::string& input) {
        return decode_uri(input);
    });

    cgltf_table.set_function("num-components", [](const sol::object& type) {
        if (type.is<int>()) {
            return cgltf_num_components(static_cast<cgltf_type>(type.as<int>()));
        }
        if (type.is<std::string>()) {
            std::string value = type.as<std::string>();
            if (value == "scalar") {
                return cgltf_num_components(cgltf_type_scalar);
            }
            if (value == "vec2") {
                return cgltf_num_components(cgltf_type_vec2);
            }
            if (value == "vec3") {
                return cgltf_num_components(cgltf_type_vec3);
            }
            if (value == "vec4") {
                return cgltf_num_components(cgltf_type_vec4);
            }
            if (value == "mat2") {
                return cgltf_num_components(cgltf_type_mat2);
            }
            if (value == "mat3") {
                return cgltf_num_components(cgltf_type_mat3);
            }
            if (value == "mat4") {
                return cgltf_num_components(cgltf_type_mat4);
            }
            throw sol::error("cgltf.num-components invalid type: " + value);
        }
        throw sol::error("cgltf.num-components expects a string or integer");
    });

    cgltf_table.set_function("malloc", [](cgltf_size size) -> void* {
        return std::malloc(size);
    });

    cgltf_table.set_function("free", [](void* ptr) {
        std::free(ptr);
    });

    cgltf_table.new_usertype<CgltfDataHandle>("CgltfData",
        sol::no_constructor,
        "drop", &CgltfDataHandle::drop,
        "valid", &CgltfDataHandle::valid,
        "to-table", [lua](const CgltfDataHandle& handle) {
            const cgltf_data* data = require_data(handle);
            CgltfConverter converter { lua, data };
            return converter.data_to_table();
        },
        "json", [](const CgltfDataHandle& handle) -> sol::optional<std::string> {
            const cgltf_data* data = require_data(handle);
            if (!data->json || data->json_size == 0) {
                return sol::nullopt;
            }
            return std::string(data->json, data->json + data->json_size);
        },
        "bin", [](const CgltfDataHandle& handle) -> sol::optional<std::string> {
            const cgltf_data* data = require_data(handle);
            if (!data->bin || data->bin_size == 0) {
                return sol::nullopt;
            }
            return std::string(static_cast<const char*>(data->bin),
                static_cast<const char*>(data->bin) + data->bin_size);
        },
        "buffer-data", [](const CgltfDataHandle& handle, cgltf_size index) -> sol::optional<std::string> {
            const cgltf_data* data = require_data(handle);
            cgltf_size buffer_index = clamp_index(index, data->buffers_count, "buffer");
            const cgltf_buffer& buffer = data->buffers[buffer_index];
            if (!buffer.data || buffer.size == 0) {
                return sol::nullopt;
            }
            return std::string(static_cast<const char*>(buffer.data),
                static_cast<const char*>(buffer.data) + buffer.size);
        },
        "buffer-view-data", [](const CgltfDataHandle& handle, cgltf_size index) -> sol::optional<std::string> {
            const cgltf_data* data = require_data(handle);
            cgltf_size view_index = clamp_index(index, data->buffer_views_count, "buffer-view");
            const cgltf_buffer_view& view = data->buffer_views[view_index];
            const char* start = nullptr;
            if (view.data) {
                start = static_cast<const char*>(view.data);
            } else if (view.buffer && view.buffer->data) {
                start = static_cast<const char*>(view.buffer->data) + view.offset;
            }
            if (!start || view.size == 0) {
                return sol::nullopt;
            }
            return std::string(start, start + view.size);
        },
        "load-buffers", [lua](const CgltfDataHandle& handle, sol::object options, sol::optional<std::string> path) {
            cgltf_data* data = require_data(handle);
            ParsedCgltfOptions parsed = parse_cgltf_options(lua, options);
            const char* gltf_path = path ? path->c_str() : nullptr;
            cgltf_result result = cgltf_load_buffers(&parsed.options, data, gltf_path);
            if (result != cgltf_result_success) {
                std::string message = "cgltf.load-buffers failed: ";
                message += cgltf_result_to_string(result);
                if (!parsed.context.last_error.empty()) {
                    message += " (" + parsed.context.last_error + ")";
                }
                throw sol::error(message);
            }
        },
        "validate", [](const CgltfDataHandle& handle) {
            cgltf_data* data = require_data(handle);
            cgltf_result result = cgltf_validate(data);
            if (result != cgltf_result_success) {
                std::string message = "cgltf.validate failed: ";
                message += cgltf_result_to_string(result);
                throw sol::error(message);
            }
        },
        "accessor-unpack-floats", [lua](const CgltfDataHandle& handle, cgltf_size index) {
            const cgltf_data* data = require_data(handle);
            cgltf_size accessor_index = clamp_index(index, data->accessors_count, "accessor");
            const cgltf_accessor& accessor = data->accessors[accessor_index];
            cgltf_size float_count = cgltf_accessor_unpack_floats(&accessor, nullptr, 0);
            std::vector<cgltf_float> out(float_count, 0.0f);
            if (float_count > 0) {
                cgltf_accessor_unpack_floats(&accessor, out.data(), float_count);
            }
            return make_float_table(lua, out.data(), float_count);
        },
        "accessor-read-float", [lua](const CgltfDataHandle& handle, cgltf_size accessor_index, cgltf_size element_index,
            sol::optional<cgltf_size> element_size) {
            const cgltf_data* data = require_data(handle);
            cgltf_size accessor_offset = clamp_index(accessor_index, data->accessors_count, "accessor");
            const cgltf_accessor& accessor = data->accessors[accessor_offset];
            cgltf_size size = element_size ? *element_size : cgltf_num_components(accessor.type);
            cgltf_size elem = clamp_index(element_index, accessor.count, "element");
            return cgltf_accessor_read_float_table(lua, &accessor, elem, size);
        },
        "accessor-read-uint", [lua](const CgltfDataHandle& handle, cgltf_size accessor_index, cgltf_size element_index,
            sol::optional<cgltf_size> element_size) {
            const cgltf_data* data = require_data(handle);
            cgltf_size accessor_offset = clamp_index(accessor_index, data->accessors_count, "accessor");
            const cgltf_accessor& accessor = data->accessors[accessor_offset];
            cgltf_size size = element_size ? *element_size : cgltf_num_components(accessor.type);
            cgltf_size elem = clamp_index(element_index, accessor.count, "element");
            return cgltf_accessor_read_uint_table(lua, &accessor, elem, size);
        },
        "accessor-read-index", [](const CgltfDataHandle& handle, cgltf_size accessor_index, cgltf_size element_index) {
            const cgltf_data* data = require_data(handle);
            cgltf_size accessor_offset = clamp_index(accessor_index, data->accessors_count, "accessor");
            const cgltf_accessor& accessor = data->accessors[accessor_offset];
            cgltf_size elem = clamp_index(element_index, accessor.count, "element");
            return cgltf_accessor_read_index(&accessor, elem);
        },
        "node-transform-local", [lua](const CgltfDataHandle& handle, cgltf_size node_index) {
            const cgltf_data* data = require_data(handle);
            cgltf_size node_offset = clamp_index(node_index, data->nodes_count, "node");
            const cgltf_node& node = data->nodes[node_offset];
            cgltf_float matrix[16] = {};
            cgltf_node_transform_local(&node, matrix);
            return make_float_table(lua, matrix, 16);
        },
        "node-transform-world", [lua](const CgltfDataHandle& handle, cgltf_size node_index) {
            const cgltf_data* data = require_data(handle);
            cgltf_size node_offset = clamp_index(node_index, data->nodes_count, "node");
            const cgltf_node& node = data->nodes[node_offset];
            cgltf_float matrix[16] = {};
            cgltf_node_transform_world(&node, matrix);
            return make_float_table(lua, matrix, 16);
        },
        "extras-json", [](const CgltfDataHandle& handle, const sol::table& extras) {
            const cgltf_data* data = require_data(handle);
            sol::optional<cgltf_size> start = extras["start-offset"];
            sol::optional<cgltf_size> end = extras["end-offset"];
            if (!start || !end) {
                throw sol::error("cgltf.extras-json requires start-offset and end-offset");
            }
            cgltf_extras extras_value { *start, *end };
            cgltf_size dest_size = 0;
            cgltf_result result = cgltf_copy_extras_json(data, &extras_value, nullptr, &dest_size);
            if (result != cgltf_result_success) {
                std::string message = "cgltf.extras-json failed: ";
                message += cgltf_result_to_string(result);
                throw sol::error(message);
            }
            std::vector<char> buffer(dest_size + 1, 0);
            result = cgltf_copy_extras_json(data, &extras_value, buffer.data(), &dest_size);
            if (result != cgltf_result_success) {
                std::string message = "cgltf.extras-json failed: ";
                message += cgltf_result_to_string(result);
                throw sol::error(message);
            }
            return std::string(buffer.data(), static_cast<size_t>(dest_size));
        }
    );

    return cgltf_table;
}

} // namespace

void lua_bind_cgltf(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("cgltf", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_cgltf_table(lua);
    });
}
