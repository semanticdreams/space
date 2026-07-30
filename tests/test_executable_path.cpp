#include <filesystem>
#include <iostream>
#include <string>

#include "executable_path.h"

namespace fs = std::filesystem;

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

int main(int argc, char** argv)
{
    fs::path resolved = executable_path::resolve(argc > 0 ? argv[0] : nullptr);
    if (!check(!resolved.empty(), "resolved executable path should not be empty")) {
        return 1;
    }
    if (!check(fs::exists(resolved), "resolved executable path should exist: " + resolved.string())) {
        return 1;
    }

    fs::path helper = executable_path::sibling(fs::path("/tmp/space-bin/space"), "space_cef_helper");
    if (!check(helper == fs::path("/tmp/space-bin/space_cef_helper"),
               "sibling should be next to executable")) {
        std::cerr << "actual: " << helper << "\n";
        return 1;
    }

    fs::path fallback = executable_path::sibling(fs::path(), "space_cef_helper");
    if (!check(fallback.is_absolute(), "empty executable sibling fallback should be absolute")) {
        return 1;
    }

    return 0;
}
