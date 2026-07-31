#pragma once

#include <filesystem>

namespace executable_path {

std::filesystem::path resolve(const char* argv0);
std::filesystem::path sibling(const std::filesystem::path& executablePath,
                              const std::filesystem::path& siblingName);

} // namespace executable_path
