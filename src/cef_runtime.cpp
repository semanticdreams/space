#include "cef_runtime.h"

#include <concepts>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <system_error>

#if defined(SPACE_ENABLE_CEF)
#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_command_line.h"

namespace {

class SpaceCefApp final : public CefApp {
public:
    void OnBeforeCommandLineProcessing(const CefString&, CefRefPtr<CefCommandLine> command_line) override
    {
        command_line->AppendSwitch("no-sandbox");
        command_line->AppendSwitch("disable-setuid-sandbox");
        command_line->AppendSwitch("no-zygote");
        command_line->AppendSwitch("disable-gpu");
        command_line->AppendSwitch("disable-gpu-compositing");
        command_line->AppendSwitch("enable-begin-frame-scheduling");
        command_line->AppendSwitch("disable-gpu-vsync");
        command_line->AppendSwitchWithValue("autoplay-policy", "no-user-gesture-required");
    }

private:
    IMPLEMENT_REFCOUNTING(SpaceCefApp);
};

std::mutex g_cef_mutex;
bool g_cef_initialized = false;
cef_runtime::Config g_cef_config {};
bool g_cef_has_config = false;

std::filesystem::path executable_dir_from_args(char** argv)
{
#if defined(__linux__)
    std::error_code proc_error;
    std::filesystem::path proc_exe = std::filesystem::read_symlink("/proc/self/exe", proc_error);
    if (!proc_error && !proc_exe.empty()) {
        return proc_exe.parent_path();
    }
#endif

    if (!argv || !argv[0] || argv[0][0] == '\0') {
        return std::filesystem::current_path();
    }
    std::filesystem::path argv_path(argv[0]);
    if (argv_path.is_absolute() || argv_path.has_parent_path()) {
        return std::filesystem::absolute(argv_path).parent_path();
    }
    if (const char* path_env = std::getenv("PATH")) {
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
                return std::filesystem::absolute(candidate).parent_path();
            }
            if (end == std::string::npos) {
                break;
            }
            start = end + 1;
        }
    }
    return std::filesystem::absolute(argv_path).parent_path();
}

std::filesystem::path cef_resource_dir_for_executable(char** argv)
{
    std::filesystem::path exe_dir = executable_dir_from_args(argv);
    std::filesystem::path installed_resource_dir = exe_dir / ".." / "lib" / "space" / "cef";
    if (std::filesystem::exists(installed_resource_dir / "resources.pak")) {
        return std::filesystem::weakly_canonical(installed_resource_dir);
    }
    return exe_dir;
}

void configure_resource_paths(CefSettings& settings, char** argv)
{
    std::filesystem::path resource_dir = cef_resource_dir_for_executable(argv);
    CefString(&settings.resources_dir_path) = resource_dir.string();
    CefString(&settings.locales_dir_path) = (resource_dir / "locales").string();
}

} // namespace
#endif

namespace cef_runtime {

int maybe_execute_subprocess(int argc, char** argv)
{
#if defined(SPACE_ENABLE_CEF)
    CefMainArgs main_args(argc, argv);
    CefRefPtr<CefApp> app(new SpaceCefApp());
    return CefExecuteProcess(main_args, app, nullptr);
#else
    (void)argc;
    (void)argv;
    return -1;
#endif
}

void configure_browser_process(const Config& config)
{
#if defined(SPACE_ENABLE_CEF)
    std::lock_guard<std::mutex> lock(g_cef_mutex);
    g_cef_config = config;
    g_cef_has_config = true;
#else
    (void)config;
#endif
}

bool initialize_browser_process(const Config& config)
{
#if defined(SPACE_ENABLE_CEF)
    std::lock_guard<std::mutex> lock(g_cef_mutex);
    if (g_cef_initialized) {
        return true;
    }

    CefMainArgs main_args(config.argc, config.argv);
    CefRefPtr<CefApp> app(new SpaceCefApp());

    CefSettings settings;
    settings.no_sandbox = true;
    settings.windowless_rendering_enabled = true;
    settings.multi_threaded_message_loop = false;

#if defined(__linux__)
    configure_resource_paths(settings, config.argv);
#endif
    {
        std::filesystem::path cache_root = std::filesystem::temp_directory_path() / "space" / "cef-cache";
        std::filesystem::create_directories(cache_root);
        CefString(&settings.root_cache_path) = cache_root.string();
        CefString(&settings.cache_path) = (cache_root / "profile").string();
    }

    if (!config.helper_executable_path.empty()) {
        CefString(&settings.browser_subprocess_path) = config.helper_executable_path;
    }

    if (!CefInitialize(main_args, settings, app, nullptr)) {
        std::cerr << "Failed to initialize CEF browser process\n";
        return false;
    }

    g_cef_initialized = true;
    return true;
#else
    (void)config;
    return false;
#endif
}

bool ensure_initialized()
{
#if defined(SPACE_ENABLE_CEF)
    std::lock_guard<std::mutex> lock(g_cef_mutex);
    if (g_cef_initialized) {
        return true;
    }
    if (!g_cef_has_config) {
        return false;
    }

    CefMainArgs main_args(g_cef_config.argc, g_cef_config.argv);
    CefRefPtr<CefApp> app(new SpaceCefApp());

    CefSettings settings;
    settings.no_sandbox = true;
    settings.windowless_rendering_enabled = true;
    settings.multi_threaded_message_loop = false;

#if defined(__linux__)
    configure_resource_paths(settings, g_cef_config.argv);
#endif
    {
        std::filesystem::path cache_root = std::filesystem::temp_directory_path() / "space" / "cef-cache";
        std::filesystem::create_directories(cache_root);
        CefString(&settings.root_cache_path) = cache_root.string();
        CefString(&settings.cache_path) = (cache_root / "profile").string();
    }

    if (!g_cef_config.helper_executable_path.empty()) {
        CefString(&settings.browser_subprocess_path) = g_cef_config.helper_executable_path;
    }

    if (!CefInitialize(main_args, settings, app, nullptr)) {
        std::cerr << "Failed to initialize CEF browser process\n";
        return false;
    }

    g_cef_initialized = true;
    return true;
#else
    return false;
#endif
}

void do_message_loop_work()
{
#if defined(SPACE_ENABLE_CEF)
    if (!g_cef_initialized) {
        return;
    }
    CefDoMessageLoopWork();
#endif
}

void shutdown()
{
#if defined(SPACE_ENABLE_CEF)
    std::lock_guard<std::mutex> lock(g_cef_mutex);
    if (!g_cef_initialized) {
        return;
    }
    CefShutdown();
    g_cef_initialized = false;
#endif
}

bool is_initialized()
{
#if defined(SPACE_ENABLE_CEF)
    std::lock_guard<std::mutex> lock(g_cef_mutex);
    return g_cef_initialized;
#else
    return false;
#endif
}

} // namespace cef_runtime
