#pragma once

#include <memory>
#include <sol/sol.hpp>

struct cgltf_data;

class CgltfDataHandle {
public:
    explicit CgltfDataHandle(cgltf_data* data_ptr);

    cgltf_data* get() const;
    bool valid() const;
    void drop();

private:
    std::unique_ptr<cgltf_data, void (*)(cgltf_data*)> data;
};

CgltfDataHandle cgltf_adopt_data(cgltf_data* data_ptr);

void lua_bind_cgltf(sol::state& lua);
