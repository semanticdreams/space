#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <system_error>
#include <vector>
#include <SDL3/SDL_main.h>

#include <CLI/CLI.hpp>

#include "dotenv.h"
#include "lua_callbacks.h"
#include "lua_jobs.h"
#include "lua_keyring.h"
#include "lua_runtime.h"
#include "lua_http_server.h"
#include "lua_engine.h"
#include "log.h"
#include "resource_manager.h"
#include "cef_runtime.h"

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

bool set_env_var(const char* key, const char* value)
{
#if defined(_WIN32)
    return _putenv_s(key, value) == 0;
#else
    return setenv(key, value, 1) == 0;
#endif
}

void configure_audio_env(const std::string& entryScript)
{
    const char* explicitDriver = std::getenv("SPACE_AUDIO_DRIVER");
    const char* disableAudio = std::getenv("SPACE_DISABLE_AUDIO");
    const char* alsoftDrivers = std::getenv("ALSOFT_DRIVERS");
    const char* ci = std::getenv("CI");

    if (explicitDriver) {
        set_env_var("ALSOFT_DRIVERS", explicitDriver);
        return;
    }

    bool shouldDisable = (disableAudio && std::string(disableAudio) == "1")
                         || (!entryScript.empty() && entryScript == "test")
                         || (ci && std::string(ci) == "true");
    if (shouldDisable && !alsoftDrivers) {
        set_env_var("ALSOFT_DRIVERS", "null");
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

std::string sibling_path(const std::string& file_path, const std::string& sibling_name)
{
    std::filesystem::path executable_path;
#if defined(__linux__)
    std::error_code proc_error;
    executable_path = std::filesystem::read_symlink("/proc/self/exe", proc_error);
    if (proc_error) {
        executable_path.clear();
    }
#endif

    if (executable_path.empty() && !file_path.empty()) {
        std::filesystem::path argv_path(file_path);
        if (argv_path.is_absolute() || argv_path.has_parent_path()) {
            executable_path = std::filesystem::absolute(argv_path);
        } else if (const char* path_env = std::getenv("PATH")) {
            std::string search_path(path_env);
            size_t start = 0;
            while (start <= search_path.size()) {
                size_t end = search_path.find(':', start);
                std::string dir = search_path.substr(start, end == std::string::npos ? std::string::npos : end - start);
                if (dir.empty()) {
                    dir = ".";
                }
                std::filesystem::path candidate = std::filesystem::path(dir) / argv_path;
                if (std::filesystem::exists(candidate)) {
                    executable_path = std::filesystem::absolute(candidate);
                    break;
                }
                if (end == std::string::npos) {
                    break;
                }
                start = end + 1;
            }
        }
    }

    if (executable_path.empty()) {
        return std::filesystem::absolute(std::filesystem::path(sibling_name)).string();
    }
    std::error_code canonical_error;
    executable_path = std::filesystem::weakly_canonical(executable_path, canonical_error);
    std::filesystem::path parent = executable_path.parent_path();
    if (parent.empty()) {
        return std::filesystem::absolute(std::filesystem::path(sibling_name)).string();
    }
    return std::filesystem::absolute(parent / sibling_name).string();
}

int main(int argc, char *argv[])
{
    LOG_CONFIG.reporting_level = Debug;
    LOG_CONFIG.restart = true;
    log_init(LOG_CONFIG);

#if defined(SPACE_ENABLE_CEF)
    bool skip_cef = false;
    if (const char* skip_cef_env = std::getenv("SPACE_SKIP_CEF")) {
        std::string value(skip_cef_env);
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
            return static_cast<char>(std::tolower(ch));
        });
        skip_cef = (value == "1" || value == "true" || value == "on");
    }
#endif

    bool run_repl = false;
    bool no_dotenv = false;
    bool dotenv_override = false;
    std::string dotenv_path = ".env";
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
    app.add_flag("--repl", run_repl, "Start embedded Fennel REPL (default entrypoint is -m main)");
    app.add_option("--dotenv", dotenv_path, "Path to dotenv file to load before startup")->expected(1);
    app.add_flag("--no-dotenv", no_dotenv, "Disable dotenv loading");
    app.add_flag("--dotenv-override", dotenv_override, "Allow dotenv values to override existing environment variables");
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
        if (arg == "--dotenv") {
            if (i + 1 >= argc) {
                std::cerr << "error: --dotenv requires a path\n";
                std::cerr << app.help() << "\n";
                return 2;
            }
            cli_args.push_back(arg);
            cli_args.push_back(argv[i + 1]);
            i++;
            continue;
        }
        if (arg.rfind("--dotenv=", 0) == 0) {
            cli_args.push_back(arg);
            continue;
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
        entry_target = "main";
        entry_display = entry_target;
        entry_mode = EntryMode::Module;
    }

    try {
        std::reverse(cli_args.begin(), cli_args.end());
        app.parse(std::move(cli_args));
    }
    catch (const CLI::ParseError &e) {
        return app.exit(e);
    }

    bool load_dotenv = !no_dotenv;
    if (load_dotenv) {
        bool dotenv_loaded = dotenv::load_dotenv_file(dotenv_path, dotenv_override);
        if (!dotenv_loaded && dotenv_path != ".env") {
            std::cerr << "warning: failed to load dotenv file: " << dotenv_path << "\n";
        }
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

#if defined(SPACE_ENABLE_CEF)
    if (!skip_cef) {
        cef_runtime::Config cef_config;
        cef_config.argc = argc;
        cef_config.argv = argv;
        cef_config.helper_executable_path = sibling_path(argv[0], "space_cef_helper");
        cef_runtime::configure_browser_process(cef_config);
    }
#endif

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
            log_write_file_only("lua", Error, std::string("REPL startup error: ") + e.what());
            std::cerr << "REPL startup error: " << e.what() << "\n";
            return 1;
        }
        return 0;
    }

    if (entry_mode == EntryMode::Command || entry_mode == EntryMode::Stdin) {
        try {
            std::string source = (entry_mode == EntryMode::Stdin) ? read_stdin() : entry_target;
            runtime.execute_fennel(source);
        }
        catch (const sol::error &e) {
            log_write_file_only("lua", Error, std::string("Lua error: ") + e.what());
            std::cerr << "Lua error: " << e.what() << "\n";
            return 1;
        }
    } else if (entry_mode == EntryMode::File) {
        try {
            if (ends_with(entry_target, ".lua")) {
                runtime.execute_lua_file(entry_target);
            } else {
                runtime.execute_fennel_file(entry_target);
            }
        }
        catch (const sol::error &e) {
            log_write_file_only("lua", Error, std::string("Lua error: ") + e.what());
            std::cerr << "Lua error: " << e.what() << "\n";
            return 1;
        }
    } else {
        try {
            if (module_function.empty()) {
                runtime.require_module(module_name_target);
            } else {
                runtime.execute_module_function(module_name_target, module_function);
            }
        }
        catch (const sol::error &e) {
            log_write_file_only("lua", Error, std::string("Lua error: ") + e.what());
            std::cerr << "Lua error: " << e.what() << "\n";
            return 1;
        }
    }

    if (lua_engine_has_active()) {
        lua_engine_shutdown_active();
    } else {
        lua_keyring_drop(lua);
        lua_jobs_clear_callbacks();
        lua_http_server_shutdown_all();
        lua_callbacks_shutdown();
        ResourceManager::clearPending();
    }
#if defined(SPACE_ENABLE_CEF)
    cef_runtime::shutdown();
#endif
	return 0;
}
