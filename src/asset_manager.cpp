#include <cstdlib>
#include <filesystem>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

#include "appdirs.h"
#include "asset_manager.h"

namespace fs = std::filesystem;

// Initialize static variables
std::string AssetManager::systemAssetsRoot = "/usr/share/space/assets";
std::optional<fs::path> AssetManager::executablePath;

namespace {

fs::path normalized(const fs::path& path)
{
    std::error_code ec;
    fs::path result = fs::weakly_canonical(fs::absolute(path, ec), ec);
    return ec ? fs::absolute(path).lexically_normal() : result;
}

std::string dedup_key(const fs::path& root)
{
    std::error_code ec;
    fs::path norm = fs::weakly_canonical(fs::absolute(root, ec), ec);
    if (ec) {
        norm = fs::absolute(root).lexically_normal();
    }
    return norm.string();
}

} // namespace

void AssetManager::setExecutablePath(const fs::path& path)
{
    if (path.empty()) {
        executablePath = std::nullopt;
    } else {
        executablePath = normalized(path);
    }
}

void AssetManager::clearExecutablePathForTests()
{
    executablePath = std::nullopt;
}

std::string AssetManager::getAssetPath(const std::string& relativePath)
{
    struct Candidate {
        fs::path root;
        std::string label;
    };

    std::vector<Candidate> candidates;
    std::vector<std::string> dedupKeys;
    std::vector<std::string> searched;

    auto addCandidate = [&](const fs::path& root, const std::string& label) {
        std::string key = dedup_key(root);
        for (const std::string& existing : dedupKeys) {
            if (existing == key) {
                searched.push_back(label + ": " + (root / relativePath).string() + " (deduplicated)");
                return;
            }
        }
        dedupKeys.push_back(key);
        candidates.push_back({root, label});
    };

    // 1. SPACE_ASSETS_PATH (highest priority override)
    const char* envAssetsPath = std::getenv("SPACE_ASSETS_PATH");
    if (envAssetsPath && envAssetsPath[0] != '\0') {
        fs::path envRoot(envAssetsPath);
        addCandidate(envRoot, "SPACE_ASSETS_PATH");
    }

    // 2. User data assets
    {
        fs::path userDataRoot = fs::path(get_user_data_dir("space")) / "assets";
        addCandidate(userDataRoot, "user-data");
    }

    // 3. Executable sibling assets
    // 4. Executable-relative ../share/space/assets
    // 5. Executable-relative ../Resources/assets
    if (executablePath.has_value()) {
        fs::path exeDir = executablePath->parent_path();

        // 3. <executable-dir>/assets
        {
            fs::path siblingRoot = exeDir / "assets";
            if (!siblingRoot.empty()) {
                addCandidate(siblingRoot, "executable-sibling");
            }
        }

        // 4. <executable-dir>/../share/space/assets
        {
            fs::path shareRoot = exeDir / ".." / "share" / "space" / "assets";
            addCandidate(shareRoot, "executable-share");
        }

        // 5. <executable-dir>/../Resources/assets
        {
            fs::path resRoot = exeDir / ".." / "Resources" / "assets";
            addCandidate(resRoot, "executable-resources");
        }
    }

    // 6. CWD/assets fallback
    {
        fs::path cwdRoot = fs::current_path() / "assets";
        addCandidate(cwdRoot, "cwd");
    }

    // 7. System assets root
    {
        addCandidate(fs::path(systemAssetsRoot), "system");
    }

    // Probe candidates in order
    for (const auto& candidate : candidates) {
        fs::path fullPath = (candidate.root / relativePath).lexically_normal();
        std::error_code ec;
        if (fs::exists(fullPath, ec)) {
            return fs::absolute(fullPath).string();
        }
        searched.push_back(candidate.label + ": " + fullPath.string());
    }

    // Not found — build diagnostic error
    std::ostringstream oss;
    oss << "Asset not found: " << relativePath << "\nSearched paths:\n";
    for (const std::string& s : searched) {
        oss << "  " << s << "\n";
    }
    throw std::runtime_error(oss.str());
}
