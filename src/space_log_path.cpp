#include "space_log_path.h"

#include <cstdlib>
#include <stdexcept>
#include <string>
#include <system_error>

#include "appdirs.h"

namespace fs = std::filesystem;

namespace space_log {

fs::path resolve_log_dir()
{
    if (const char* envLogDir = std::getenv("SPACE_LOG_DIR")) {
        if (envLogDir[0] != '\0') {
            return fs::path(envLogDir);
        }
    }
    return fs::path(get_user_log_dir("space"));
}

fs::path resolve_log_path()
{
    return resolve_log_dir() / "space.log";
}

void ensure_log_directory(const fs::path& logPath)
{
    fs::path parent = logPath.parent_path();
    if (parent.empty()) {
        throw std::runtime_error("log path has no parent directory: " + logPath.string());
    }

    std::error_code ec;
    if (fs::exists(parent, ec)) {
        if (!fs::is_directory(parent, ec)) {
            throw std::runtime_error("log directory is not a directory: " + parent.string());
        }
        return;
    }

    if (!fs::create_directories(parent, ec) && ec) {
        throw std::runtime_error("failed to create log directory " + parent.string() + ": " + ec.message());
    }
    if (!fs::is_directory(parent, ec)) {
        throw std::runtime_error("log directory is not a directory after creation: " + parent.string());
    }
}

} // namespace space_log
