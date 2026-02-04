#pragma once

#include <string>
#include <vector>

struct GltfMeshBatch {
    std::vector<float> vertices;
    int image_index { 0 };
    std::string image_uri;
    std::string image_bytes;
};

struct GltfMeshJobResult {
    std::vector<GltfMeshBatch> batches;
    float bounds_min[3] { 0.0f, 0.0f, 0.0f };
    float bounds_max[3] { 0.0f, 0.0f, 0.0f };
    bool has_bounds { false };
};
