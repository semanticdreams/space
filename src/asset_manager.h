#pragma once

#include <filesystem>
#include <optional>
#include <string>

class AssetManager {
public:
    static std::string getAssetPath(const std::string& relativePath);
    static void setExecutablePath(const std::filesystem::path& executablePath);
    static void clearExecutablePathForTests();

private:
    static std::string systemAssetsRoot;
    static std::optional<std::filesystem::path> executablePath;
};
