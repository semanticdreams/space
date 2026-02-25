#include "cef_runtime.h"

#include <concepts>
#include <filesystem>
#include <iostream>
#include <mutex>

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
    if (config.argv && config.argv[0] && config.argv[0][0] != '\0') {
        std::filesystem::path exe_path = std::filesystem::absolute(std::filesystem::path(config.argv[0]));
        std::filesystem::path exe_dir = exe_path.parent_path();
        CefString(&settings.resources_dir_path) = exe_dir.string();
        CefString(&settings.locales_dir_path) = (exe_dir / "locales").string();
    }
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
    if (g_cef_config.argv && g_cef_config.argv[0] && g_cef_config.argv[0][0] != '\0') {
        std::filesystem::path exe_path = std::filesystem::absolute(std::filesystem::path(g_cef_config.argv[0]));
        std::filesystem::path exe_dir = exe_path.parent_path();
        CefString(&settings.resources_dir_path) = exe_dir.string();
        CefString(&settings.locales_dir_path) = (exe_dir / "locales").string();
    }
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
