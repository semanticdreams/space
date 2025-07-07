#include <filesystem>
#include <stdexcept>

#include "asset_manager.h"

namespace fs = std::filesystem;

// Initialize static variable
std::string AssetManager::systemAssetsRoot = "/usr/share/space/assets";

std::string AssetManager::getAssetPath(const std::string& relativePath) {
    // Look for asset in env var
    if (const char* envAssetsPath = std::getenv("SPACE_ASSETS_PATH")) {
        fs::path envPath = fs::path(envAssetsPath) / relativePath;
        if (fs::exists(envPath)) {
            return envPath.string();
        }
    }
    // Look for asset in local assets folder
    fs::path devPath = fs::current_path() / "assets" / relativePath;
    if (fs::exists(devPath)) {
        return devPath.string();
    }

    // Look for asset in system assets folder
    fs::path sysPath = fs::path(systemAssetsRoot) / relativePath;
    if (fs::exists(sysPath)) {
        return sysPath.string();
    }

    // If not found, throw an error
    throw std::runtime_error("Asset not found: " + relativePath);
}
