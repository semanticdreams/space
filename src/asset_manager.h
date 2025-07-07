#pragma once

#include <string>

class AssetManager {
public:
    // Find the full path to an asset
    static std::string getAssetPath(const std::string& relativePath);

private:
    static std::string systemAssetsRoot;
};
