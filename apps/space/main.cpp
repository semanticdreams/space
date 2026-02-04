#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include <CLI/CLI.hpp>

#include "lua_callbacks.h"
#include "lua_jobs.h"
#include "lua_keyring.h"
#include "lua_runtime.h"
#include "lua_engine.h"
#include "log.h"
#include "resource_manager.h"

LogConfig LOG_CONFIG = {};

// Use Graphics Card
#define DWORD unsigned int
#if defined(WIN32) || defined(_WIN32)
extern "C" { __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001; }
extern "C" { __declspec(dllexport) DWORD AmdPowerXpressRequestHighPerformance = 0x00000001; }
#else
extern "C" { int NvOptimusEnablement = 1; }
extern "C" { int AmdPowerXpressRequestHighPerformance = 1; }
#endif

void configure_audio_env(const std::string& entryScript)
{
    const char* explicitDriver = std::getenv("SPACE_AUDIO_DRIVER");
    const char* disableAudio = std::getenv("SPACE_DISABLE_AUDIO");
    const char* alsoftDrivers = std::getenv("ALSOFT_DRIVERS");
    const char* ci = std::getenv("CI");

    if (explicitDriver) {
        setenv("ALSOFT_DRIVERS", explicitDriver, 1);
        return;
    }

    bool shouldDisable = (disableAudio && std::string(disableAudio) == "1")
                         || (!entryScript.empty() && entryScript == "test")
                         || (ci && std::string(ci) == "true");
    if (shouldDisable && !alsoftDrivers) {
        setenv("ALSOFT_DRIVERS", "null", 1);
    }
}

bool ends_with(const std::string& value, const std::string& suffix)
{
    if (suffix.size() > value.size()) {
        return false;
    }
    return std::equal(suffix.rbegin(), suffix.rend(), value.rbegin());
}

std::string basename_without_extension(const std::string& path)
{
    if (path == "-") {
        return path;
    }
    size_t sep = path.find_last_of("/\\");
    std::string name = (sep == std::string::npos) ? path : path.substr(sep + 1);
    size_t dot = name.find_last_of('.');
    if (dot == std::string::npos) {
        return name;
    }
    return name.substr(0, dot);
}

std::string read_stdin()
{
    std::string input;
    std::string line;
    while (std::getline(std::cin, line)) {
        input.append(line);
        input.push_back('\n');
    }
    return input;
}

int main(int argc, char *argv[])
{
    LOG_CONFIG.reporting_level = Debug;
    LOG_CONFIG.restart = true;
    log_init(LOG_CONFIG);

    bool run_repl = false;
    std::string command_source;
    std::string module_name;

    enum class EntryMode {
        Module,
        File,
        Command,
        Stdin
    };
    EntryMode entry_mode = EntryMode::Module;
    std::string entry_target = "main";
    std::string entry_display = "main";
    std::vector<std::string> fennel_args;

    std::vector<std::string> cli_args;
    cli_args.reserve(static_cast<size_t>(argc));

    CLI::App app("space");
    app.usage("space [option] ... [-c cmd | -m mod[:fn] | file | -] [arg] ...");
    app.add_flag("--repl", run_repl, "Start embedded Fennel REPL");
    app.add_option("-c", command_source, "Program passed in as string")->expected(1);
    app.add_option("-m", module_name, "Run library module or module function")->expected(1);

    bool entry_set = false;
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--") {
            if (i + 1 < argc) {
                entry_target = argv[i + 1];
                entry_display = entry_target;
                entry_mode = (entry_target == "-") ? EntryMode::Stdin : EntryMode::File;
                fennel_args.assign(argv + i + 2, argv + argc);
                entry_set = true;
            }
            break;
        }
        if (arg == "-c") {
            if (i + 1 >= argc) {
                std::cerr << "error: -c requires an argument\n";
                std::cerr << app.help() << "\n";
                return 2;
            }
            entry_mode = EntryMode::Command;
            entry_target = argv[i + 1];
            entry_display = "-c";
            fennel_args.assign(argv + i + 2, argv + argc);
            entry_set = true;
            break;
        }
        if (arg == "-m") {
            if (i + 1 >= argc) {
                std::cerr << "error: -m requires an argument\n";
                std::cerr << app.help() << "\n";
                return 2;
            }
            entry_mode = EntryMode::Module;
            entry_target = argv[i + 1];
            entry_display = entry_target;
            fennel_args.assign(argv + i + 2, argv + argc);
            entry_set = true;
            break;
        }
        if (!arg.empty() && arg[0] == '-' && arg != "-") {
            cli_args.push_back(arg);
            continue;
        }
        entry_target = arg;
        entry_display = entry_target;
        entry_mode = (entry_target == "-") ? EntryMode::Stdin : EntryMode::File;
        fennel_args.assign(argv + i + 1, argv + argc);
        entry_set = true;
        break;
    }

    if (!entry_set) {
        entry_target.clear();
        entry_display = argv[0];
        entry_mode = EntryMode::Module;
        run_repl = true;
    }

    try {
        std::reverse(cli_args.begin(), cli_args.end());
        app.parse(std::move(cli_args));
    }
    catch (const CLI::ParseError &e) {
        return app.exit(e);
    }

    std::string module_name_target = entry_target;
    std::string module_function;
    if (entry_mode == EntryMode::Module) {
        size_t colon = entry_target.rfind(':');
        if (colon != std::string::npos) {
            if (colon == 0 || colon + 1 >= entry_target.size()) {
                std::cerr << "error: -m expects mod or mod:fn\n";
                return 2;
            }
            module_name_target = entry_target.substr(0, colon);
            module_function = entry_target.substr(colon + 1);
        }
    }

    std::string audio_tag;
    if (entry_mode == EntryMode::Module) {
        audio_tag = module_name_target;
    } else if (entry_mode == EntryMode::File) {
        audio_tag = basename_without_extension(entry_target);
    }
    configure_audio_env(audio_tag);

    LuaRuntime runtime;
    runtime.init();
    runtime.install_fennel(true);
    sol::state& lua = runtime.state();
    sol::table arg = lua.create_table();
    arg[0] = entry_display;
    for (size_t i = 0; i < fennel_args.size(); i++) {
        arg[static_cast<int>(i + 1)] = fennel_args[i];
    }
    lua["arg"] = arg;

    sol::table app_config = lua.create_table();
    app_config["run-main"] = (entry_mode == EntryMode::Module && module_name_target == "main" && module_function.empty());
    lua["package"]["preload"]["app-config"] = [app_config](sol::this_state ts) -> sol::object {
        sol::state_view lua_view(ts);
        return sol::make_object(lua_view, app_config);
    };

    if (run_repl) {
        try {
            lua.script(R"(
            print("Fennel REPL (embedded). Ctrl+D to exit.")
            local fennel = require("fennel")
            fennel.repl()
        )");
        }
        catch (const sol::error &e) {
            std::cerr << "REPL startup error: " << e.what() << "\n";
            return 1;
        }
        return 0;
    }

    if (entry_mode == EntryMode::Command || entry_mode == EntryMode::Stdin) {
        try {
            sol::function require = lua["require"];
            sol::table fennel = require("fennel");
            sol::function eval = fennel["eval"];
            std::string source = (entry_mode == EntryMode::Stdin) ? read_stdin() : entry_target;
            eval(source);
        }
        catch (const sol::error &e) {
            std::cerr << "Lua error: " << e.what() << "\n";
            return 1;
        }
    } else if (entry_mode == EntryMode::File) {
        try {
            if (ends_with(entry_target, ".lua")) {
                lua.script_file(entry_target);
            } else {
                sol::function require = lua["require"];
                sol::table fennel = require("fennel");
                sol::function dofile = fennel["dofile"];
                dofile(entry_target);
            }
        }
        catch (const sol::error &e) {
            std::cerr << "Lua error: " << e.what() << "\n";
            return 1;
        }
    } else {
        if (module_function.empty()) {
            runtime.require_module(module_name_target);
        } else {
            try {
                sol::function require = lua["require"];
                sol::object module_obj = require(module_name_target);
                if (!module_obj.is<sol::table>()) {
                    std::cerr << "Lua error: module " << module_name_target
                              << " did not return a table for :" << module_function << "\n";
                    return 1;
                }
                sol::table module_table = module_obj.as<sol::table>();
                sol::object function_obj = module_table[module_function];
                if (!function_obj.is<sol::function>()) {
                    std::cerr << "Lua error: module " << module_name_target
                              << " missing function " << module_function << "\n";
                    return 1;
                }
                sol::function fn = function_obj.as<sol::function>();
                fn();
            }
            catch (const sol::error &e) {
                std::cerr << "Lua error: " << e.what() << "\n";
                return 1;
            }
        }
    }

    if (lua_engine_has_active()) {
        lua_engine_shutdown_active();
    } else {
        lua_keyring_drop(lua);
        lua_jobs_clear_callbacks();
        lua_callbacks_shutdown();
        ResourceManager::clearPending();
    }
	return 0;
}
