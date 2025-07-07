#include "appdirs.h"

#include <cstdlib>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _WIN32
    #include <windows.h>
    #include <shlobj.h>
    #include <direct.h>
    #pragma comment(lib, "shell32.lib")
#else
    #include <unistd.h>
    #include <pwd.h>
    #include <errno.h>
    #include <cstring>
#endif

static std::string get_home_dir() {
#ifdef _WIN32
    char path[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_PROFILE, NULL, 0, path))) {
        return std::string(path);
    }
    return "";
#else
    const char* home = getenv("HOME");
    if (home) return std::string(home);

    struct passwd* pw = getpwuid(getuid());
    return pw ? std::string(pw->pw_dir) : "";
#endif
}

static bool create_directory(const std::string& path) {
#ifdef _WIN32
    return _mkdir(path.c_str()) == 0 || errno == EEXIST;
#else
    return mkdir(path.c_str(), 0755) == 0 || errno == EEXIST;
#endif
}

std::string get_user_data_dir(const std::string& app_name) {
    std::string path;

#ifdef _WIN32
    char buf[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_APPDATA, NULL, 0, buf))) {
        path = std::string(buf) + "\\" + app_name;
    } else {
        path = get_home_dir() + "\\" + app_name;
    }
#elif __APPLE__
    path = get_home_dir() + "/Library/Application Support/" + app_name;
#else
    const char* xdg = getenv("XDG_DATA_HOME");
    if (xdg) {
        path = std::string(xdg) + "/" + app_name;
    } else {
        path = get_home_dir() + "/.local/share/" + app_name;
    }
#endif

    // Create the directory if it doesn't exist
    if (!create_directory(path)) {
        // Optionally, handle errors here or log them
    }

    return path;
}
