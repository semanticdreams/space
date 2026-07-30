#include "executable_path.h"

#include <cstdlib>
#include <cstdint>
#include <string>
#include <system_error>

#if defined(__linux__)
#include <unistd.h>
#elif defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <vector>
#endif

namespace fs = std::filesystem;

namespace {

fs::path canonical_or_absolute(const fs::path& path)
{
    if (path.empty()) {
        return fs::path();
    }
    std::error_code ec;
    fs::path absolute = path.is_absolute() ? path : fs::absolute(path, ec);
    if (ec) {
        absolute = path;
    }
    fs::path canonical = fs::weakly_canonical(absolute, ec);
    return ec ? absolute.lexically_normal() : canonical;
}

fs::path platform_executable_path()
{
#if defined(__linux__)
    std::error_code ec;
    fs::path procExe = fs::read_symlink("/proc/self/exe", ec);
    if (!ec && !procExe.empty()) {
        return procExe;
    }
#elif defined(_WIN32)
    std::string buffer(MAX_PATH, '\0');
    DWORD size = GetModuleFileNameA(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (size > 0 && size < buffer.size()) {
        buffer.resize(size);
        return fs::path(buffer);
    }
#elif defined(__APPLE__)
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    if (size > 0) {
        std::vector<char> buffer(size);
        if (_NSGetExecutablePath(buffer.data(), &size) == 0) {
            return fs::path(buffer.data());
        }
    }
#endif
    return fs::path();
}

char path_separator()
{
#if defined(_WIN32)
    return ';';
#else
    return ':';
#endif
}

fs::path lookup_on_path(const fs::path& argvPath)
{
    const char* pathEnv = std::getenv("PATH");
    if (!pathEnv || pathEnv[0] == '\0') {
        return fs::path();
    }
    std::string searchPath(pathEnv);
    size_t start = 0;
    while (start <= searchPath.size()) {
        size_t end = searchPath.find(path_separator(), start);
        std::string dir = searchPath.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (dir.empty()) {
            dir = ".";
        }
        fs::path candidate = fs::path(dir) / argvPath;
        std::error_code ec;
        if (fs::exists(candidate, ec)) {
            return candidate;
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return fs::path();
}

} // namespace

namespace executable_path {

fs::path resolve(const char* argv0)
{
    fs::path native = platform_executable_path();
    if (!native.empty()) {
        return canonical_or_absolute(native);
    }
    if (!argv0 || argv0[0] == '\0') {
        return fs::path();
    }
    fs::path argvPath(argv0);
    if (argvPath.is_absolute() || argvPath.has_parent_path()) {
        return canonical_or_absolute(argvPath);
    }
    fs::path pathCandidate = lookup_on_path(argvPath);
    if (!pathCandidate.empty()) {
        return canonical_or_absolute(pathCandidate);
    }
    return canonical_or_absolute(argvPath);
}

fs::path sibling(const fs::path& executablePath, const fs::path& siblingName)
{
    if (executablePath.empty() || executablePath.parent_path().empty()) {
        return canonical_or_absolute(siblingName);
    }
    return canonical_or_absolute(executablePath.parent_path() / siblingName);
}

} // namespace executable_path
