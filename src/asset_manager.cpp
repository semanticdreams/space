#include <filesystem>
#include <stdexcept>

#include "appdirs.h"
#include "asset_manager.h"

namespace fs = std::filesystem;

// Initialize static variable
std::string AssetManager::systemAssetsRoot = "/usr/share/space/assets";

std::string AssetManager::getAssetPath(const std::string& relativePath) {
    // Look for asset in env var
    if (const char* envAssetsPath = std::getenv("SPACE_ASSETS_PATH")) {
        fs::path envPath = fs::path(envAssetsPath) / relativePath;
        fs::path absEnvPath = fs::absolute(envPath);
        if (fs::exists(absEnvPath)) {
            return absEnvPath.string();
        }
    }

    // Look for asset in user data assets folder
    fs::path userDataPath = fs::path(get_user_data_dir("space")) / "assets" / relativePath;
    fs::path absUserDataPath = fs::absolute(userDataPath);
    if (fs::exists(absUserDataPath)) {
        return absUserDataPath.string();
    }

    // Look for asset in local assets folder
    fs::path devPath = fs::current_path() / "assets" / relativePath;
    fs::path absDevPath = fs::absolute(devPath);
    if (fs::exists(absDevPath)) {
        return absDevPath.string();
    }

    // Look for asset in system assets folder
    fs::path sysPath = fs::path(systemAssetsRoot) / relativePath;
    if (fs::exists(sysPath)) {
        return sysPath.string();
    }

    // If not found, throw an error
    throw std::runtime_error("Asset not found: " + relativePath);
}
