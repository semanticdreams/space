#include <filesystem>

#include "paths.h"

std::string join_path(const std::string& p1, const std::string& p2) {
    std::filesystem::path path1(p1);
    std::filesystem::path path2(p2);
    return (path1 / path2).string();
}
