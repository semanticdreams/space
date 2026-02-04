#include <cstdlib>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

#include "appdirs.h"

#ifdef _WIN32
    #include <windows.h>
    #include <shlobj.h>
#else
    #include <unistd.h>
    #include <pwd.h>
#endif

namespace fs = std::filesystem;

namespace {

#ifdef _WIN32
std::string get_folder_path(int csidl)
{
    char path[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, csidl, NULL, 0, path))) {
        return std::string(path);
    }
    return std::string();
}
#endif

fs::path get_env_path(const char* name)
{
    const char* value = std::getenv(name);
    if (value && value[0] != '\0') {
        return fs::path(value);
    }
    return fs::path();
}

fs::path first_path_from_env(const char* name, char separator)
{
    const char* value = std::getenv(name);
    if (!value || value[0] == '\0') {
        return fs::path();
    }
    std::string raw(value);
    std::size_t pos = raw.find(separator);
    if (pos == std::string::npos) {
        return fs::path(raw);
    }
    return fs::path(raw.substr(0, pos));
}

fs::path append_app(const fs::path& base, const std::string& app_name)
{
    if (app_name.empty()) {
        return base;
    }
    return base / app_name;
}

} // namespace

std::string get_home_dir()
{
#ifdef _WIN32
    std::string home = get_folder_path(CSIDL_PROFILE);
    if (!home.empty()) {
        return home;
    }
    fs::path env_home = get_env_path("USERPROFILE");
    if (!env_home.empty()) {
        return env_home.string();
    }
    env_home = get_env_path("HOME");
    return env_home.empty() ? std::string() : env_home.string();
#else
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') {
        return std::string(home);
    }

    struct passwd* pw = getpwuid(getuid());
    return pw ? std::string(pw->pw_dir) : std::string();
#endif
}

std::string get_tmp_dir()
{
    std::error_code ec;
    fs::path tmp = fs::temp_directory_path(ec);
    if (!ec) {
        return tmp.string();
    }

#ifdef _WIN32
    fs::path fallback = get_env_path("TEMP");
    if (fallback.empty()) {
        fallback = get_env_path("TMP");
    }
    if (fallback.empty()) {
        fallback = fs::path(get_home_dir());
    }
    return fallback.string();
#else
    return fs::path("/tmp").string();
#endif
}

std::string get_user_data_dir(const std::string& app_name)
{
    fs::path base;

#ifdef _WIN32
    base = fs::path(get_folder_path(CSIDL_APPDATA));
    if (base.empty()) {
        base = fs::path(get_home_dir());
    }
#elif __APPLE__
    base = fs::path(get_home_dir()) / "Library" / "Application Support";
#else
    base = get_env_path("XDG_DATA_HOME");
    if (base.empty()) {
        base = fs::path(get_home_dir()) / ".local" / "share";
    }
#endif

    return append_app(base, app_name).string();
}

std::string get_user_config_dir(const std::string& app_name)
{
    fs::path base;

#ifdef _WIN32
    base = fs::path(get_folder_path(CSIDL_APPDATA));
    if (base.empty()) {
        base = fs::path(get_home_dir());
    }
#elif __APPLE__
    base = fs::path(get_home_dir()) / "Library" / "Application Support";
#else
    base = get_env_path("XDG_CONFIG_HOME");
    if (base.empty()) {
        base = fs::path(get_home_dir()) / ".config";
    }
#endif

    return append_app(base, app_name).string();
}

std::string get_user_cache_dir(const std::string& app_name)
{
    fs::path base;

#ifdef _WIN32
    base = fs::path(get_folder_path(CSIDL_LOCAL_APPDATA));
    if (base.empty()) {
        base = fs::path(get_home_dir());
    }
#elif __APPLE__
    base = fs::path(get_home_dir()) / "Library" / "Caches";
#else
    base = get_env_path("XDG_CACHE_HOME");
    if (base.empty()) {
        base = fs::path(get_home_dir()) / ".cache";
    }
#endif

    return append_app(base, app_name).string();
}

std::string get_user_log_dir(const std::string& app_name)
{
#ifdef __APPLE__
    fs::path base = fs::path(get_home_dir()) / "Library" / "Logs";
    return append_app(base, app_name).string();
#elif _WIN32
    fs::path base = fs::path(get_user_data_dir(app_name));
    base /= "Logs";
    return base.string();
#else
    fs::path base = fs::path(get_user_cache_dir(app_name));
    base /= "log";
    return base.string();
#endif
}

std::string get_site_data_dir(const std::string& app_name)
{
    fs::path base;

#ifdef _WIN32
    base = fs::path(get_folder_path(CSIDL_COMMON_APPDATA));
    if (base.empty()) {
        base = fs::path(get_home_dir());
    }
#elif __APPLE__
    base = fs::path("/Library/Application Support");
#else
    base = first_path_from_env("XDG_DATA_DIRS", ':');
    if (base.empty()) {
        base = fs::path("/usr/local/share");
    }
#endif

    return append_app(base, app_name).string();
}

std::string get_site_config_dir(const std::string& app_name)
{
    fs::path base;

#ifdef _WIN32
    base = fs::path(get_folder_path(CSIDL_COMMON_APPDATA));
    if (base.empty()) {
        base = fs::path(get_home_dir());
    }
#elif __APPLE__
    base = fs::path("/Library/Application Support");
#else
    base = first_path_from_env("XDG_CONFIG_DIRS", ':');
    if (base.empty()) {
        base = fs::path("/etc/xdg");
    }
#endif

    return append_app(base, app_name).string();
}
