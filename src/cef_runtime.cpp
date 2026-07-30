#include "cef_runtime.h"

#include <concepts>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <system_error>

#include "executable_path.h"

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
        command_line->AppendSwitch("in-process-gpu");
        command_line->AppendSwitchWithValue("autoplay-policy", "no-user-gesture-required");
    }

private:
    IMPLEMENT_REFCOUNTING(SpaceCefApp);
};

std::mutex g_cef_mutex;
bool g_cef_initialized = false;
cef_runtime::Config g_cef_config {};
bool g_cef_has_config = false;

std::filesystem::path cef_resource_dir_for_executable(char** argv)
{
    std::filesystem::path executable = executable_path::resolve(argv && argv[0] ? argv[0] : nullptr);
    std::filesystem::path exeDir = executable.empty()
        ? std::filesystem::current_path()
        : executable.parent_path();

    std::filesystem::path installedResourceDir = exeDir / ".." / "lib" / "space" / "cef";
    if (std::filesystem::exists(installedResourceDir / "resources.pak")) {
        std::error_code ec;
        std::filesystem::path canonical = std::filesystem::weakly_canonical(installedResourceDir, ec);
        return ec ? installedResourceDir.lexically_normal() : canonical;
    }
    return exeDir;
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
