#pragma once

#include <string>

#ifndef SOL_ALL_SAFETIES_ON
#define SOL_ALL_SAFETIES_ON 1
#endif
#include <sol/sol.hpp>

class LuaRuntime {
public:
    LuaRuntime();
    void init();
    void install_fennel(bool correlate);
    void require_module(const std::string& name);

    sol::state& state() { return lua; }
    const std::string& assets_path() const { return assets_path_value; }
    const std::string& fennel_path() const { return fennel_path_value; }

private:
    void install_fatal_traceback();
    void install_base_bindings();
    void configure_package_paths();

    sol::state lua;
    std::string assets_path_value;
    std::string fennel_path_value;
};
