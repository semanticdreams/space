#pragma once

#include <filesystem>

namespace space_log {

std::filesystem::path resolve_log_dir();
std::filesystem::path resolve_log_path();
void ensure_log_directory(const std::filesystem::path& logPath);

} // namespace space_log
