#include "browser_system.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <concepts>
#include <iostream>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "cef_runtime.h"
#include "resource_manager.h"

#if defined(SPACE_ENABLE_CEF)
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_frame.h"
#include "include/cef_render_handler.h"
#endif

namespace browser {

namespace {

struct SurfaceFrame {
    int width { 0 };
    int height { 0 };
    std::vector<std::uint8_t> pixels;
    bool dirty { false };
};

std::string default_texture_name_for(const std::string& id)
{
    return "browser/" + id;
}

std::uint64_t frame_interval_for(std::uint32_t max_fps)
{
    if (max_fps == 0 || max_fps >= 60) {
        return 1;
    }
    std::uint64_t interval = 60 / static_cast<std::uint64_t>(max_fps);
    return interval == 0 ? 1 : interval;
}

} // namespace

struct BrowserSurfaceStateInternal {
    std::string id;
    std::string url;
    std::string texture_name;
    std::uint32_t width { 0 };
    std::uint32_t height { 0 };
    std::uint32_t max_fps { 30 };
    bool visible { true };
    std::uint64_t last_upload_frame { 0 };
    std::uint64_t paint_count { 0 };
    std::uint64_t upload_count { 0 };
    bool texture_allocated { false };
    std::mutex frame_mutex;
    SurfaceFrame pending_frame;
#if defined(SPACE_ENABLE_CEF)
    CefRefPtr<CefBrowser> browser;
    CefRefPtr<CefClient> client;
#endif
};

#if defined(SPACE_ENABLE_CEF)
class SurfaceClient final : public CefClient, public CefRenderHandler {
public:
    explicit SurfaceClient(const std::shared_ptr<BrowserSurfaceStateInternal>& state_ref)
        : state(state_ref)
    {
    }

    CefRefPtr<CefRenderHandler> GetRenderHandler() override
    {
        return this;
    }

    void GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) override
    {
        auto state_ptr = state.lock();
        if (!state_ptr) {
            rect = CefRect(0, 0, 1, 1);
            return;
        }
        rect = CefRect(0, 0, static_cast<int>(state_ptr->width), static_cast<int>(state_ptr->height));
    }

    void OnPaint(CefRefPtr<CefBrowser>,
                 PaintElementType type,
                 const RectList&,
                 const void* buffer,
                 int width,
                 int height) override
    {
        if (type != PET_VIEW || !buffer || width <= 0 || height <= 0) {
            return;
        }

        auto state_ptr = state.lock();
        if (!state_ptr) {
            return;
        }

        const std::size_t bytes = static_cast<std::size_t>(width) *
                                  static_cast<std::size_t>(height) *
                                  static_cast<std::size_t>(4);
        std::lock_guard<std::mutex> lock(state_ptr->frame_mutex);
        state_ptr->pending_frame.width = width;
        state_ptr->pending_frame.height = height;
        state_ptr->pending_frame.pixels.resize(bytes);
        std::memcpy(state_ptr->pending_frame.pixels.data(), buffer, bytes);
        state_ptr->pending_frame.dirty = true;
        state_ptr->paint_count += 1;
    }

private:
    std::weak_ptr<BrowserSurfaceStateInternal> state;

    IMPLEMENT_REFCOUNTING(SurfaceClient);
};
#endif

bool BrowserSystem::create_surface(const SurfaceConfig& config)
{
    if (config.id.empty()) {
        std::cerr << "Browser surface id is required\n";
        return false;
    }
    if (config.url.empty()) {
        std::cerr << "Browser surface url is required\n";
        return false;
    }
    if (config.width == 0 || config.height == 0) {
        std::cerr << "Browser surface dimensions must be non-zero\n";
        return false;
    }

    if (surfaces.find(config.id) != surfaces.end()) {
        std::cerr << "Browser surface already exists: " << config.id << "\n";
        return false;
    }

#if !defined(SPACE_ENABLE_CEF)
    std::cerr << "Browser surface requires build with SPACE_ENABLE_CEF=ON\n";
    return false;
#else
    if (!cef_runtime::is_initialized() && !cef_runtime::ensure_initialized()) {
        std::cerr << "Failed to initialize CEF browser process\n";
        return false;
    }

    auto state = std::make_shared<BrowserSurfaceStateInternal>();
    state->id = config.id;
    state->url = config.url;
    state->texture_name = config.texture_name.empty() ? default_texture_name_for(config.id) : config.texture_name;
    state->width = config.width;
    state->height = config.height;
    state->max_fps = config.max_fps == 0 ? 30 : config.max_fps;
    state->visible = true;
    state->last_upload_frame = 0;
    state->paint_count = 0;
    state->upload_count = 0;
    state->texture_allocated = false;

    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);

    CefBrowserSettings browser_settings;
    browser_settings.windowless_frame_rate = static_cast<int>(state->max_fps);

    CefRefPtr<CefClient> client(new SurfaceClient(state));
    CefRefPtr<CefBrowser> browser = CefBrowserHost::CreateBrowserSync(
        window_info,
        client,
        state->url,
        browser_settings,
        nullptr,
        nullptr);
    if (!browser) {
        std::cerr << "Failed to create CEF browser surface: " << config.id << "\n";
        return false;
    }

    Texture2D& texture = ResourceManager::textures[state->texture_name];
    texture.allocate(static_cast<int>(state->width), static_cast<int>(state->height), 4);
    state->texture_allocated = true;

    state->client = client;
    state->browser = browser;

    surfaces[config.id] = state;
    ordered_ids.push_back(config.id);
    return true;
#endif
}

bool BrowserSystem::destroy_surface(const std::string& id)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return false;
    }

#if defined(SPACE_ENABLE_CEF)
    if (it->second->browser) {
        it->second->browser->GetHost()->CloseBrowser(true);
        it->second->browser = nullptr;
        it->second->client = nullptr;
    }
#endif

    surfaces.erase(it);
    ordered_ids.erase(std::remove(ordered_ids.begin(), ordered_ids.end(), id), ordered_ids.end());
    return true;
}

void BrowserSystem::shutdown()
{
    std::vector<std::string> ids = ordered_ids;
    for (const std::string& id : ids) {
        destroy_surface(id);
    }
    ordered_ids.clear();
}

bool BrowserSystem::set_surface_url(const std::string& id, const std::string& url)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return false;
    }
    if (url.empty()) {
        return false;
    }

    it->second->url = url;
#if defined(SPACE_ENABLE_CEF)
    if (it->second->browser) {
        CefRefPtr<CefFrame> frame = it->second->browser->GetMainFrame();
        if (frame) {
            frame->LoadURL(url);
        }
    }
#endif
    return true;
}

void BrowserSystem::set_surface_visible(const std::string& id, bool visible)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return;
    }
    it->second->visible = visible;
}

bool BrowserSystem::set_surface_focus(const std::string& id, bool focused)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return false;
    }
#if defined(SPACE_ENABLE_CEF)
    if (it->second->browser) {
        it->second->browser->GetHost()->SetFocus(focused);
    }
#else
    (void)focused;
#endif
    return true;
}

bool BrowserSystem::send_mouse_move(const std::string& id, int x, int y, bool mouse_leave)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return false;
    }
#if defined(SPACE_ENABLE_CEF)
    if (!it->second->browser) {
        return false;
    }
    CefMouseEvent event;
    event.x = x;
    event.y = y;
    event.modifiers = 0;
    it->second->browser->GetHost()->SendMouseMoveEvent(event, mouse_leave);
#else
    (void)x;
    (void)y;
    (void)mouse_leave;
#endif
    return true;
}

bool BrowserSystem::send_mouse_click(const std::string& id, int x, int y, int button, bool mouse_up, int click_count)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return false;
    }
#if defined(SPACE_ENABLE_CEF)
    if (!it->second->browser) {
        return false;
    }

    CefBrowserHost::MouseButtonType cef_button = MBT_LEFT;
    if (button == 2) {
        cef_button = MBT_MIDDLE;
    } else if (button == 3) {
        cef_button = MBT_RIGHT;
    }

    CefMouseEvent event;
    event.x = x;
    event.y = y;
    event.modifiers = 0;
    it->second->browser->GetHost()->SendMouseClickEvent(event, cef_button, mouse_up, click_count);
#else
    (void)x;
    (void)y;
    (void)button;
    (void)mouse_up;
    (void)click_count;
#endif
    return true;
}

bool BrowserSystem::send_mouse_wheel(const std::string& id, int x, int y, int delta_x, int delta_y)
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return false;
    }
#if defined(SPACE_ENABLE_CEF)
    if (!it->second->browser) {
        return false;
    }

    CefMouseEvent event;
    event.x = x;
    event.y = y;
    event.modifiers = 0;
    it->second->browser->GetHost()->SendMouseWheelEvent(event, delta_x, delta_y);
#else
    (void)x;
    (void)y;
    (void)delta_x;
    (void)delta_y;
#endif
    return true;
}

std::optional<std::string> BrowserSystem::get_surface_texture_name(const std::string& id) const
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return std::nullopt;
    }
    return it->second->texture_name;
}

std::optional<BrowserSystem::SurfaceStats> BrowserSystem::get_surface_stats(const std::string& id) const
{
    auto it = surfaces.find(id);
    if (it == surfaces.end()) {
        return std::nullopt;
    }
    const std::shared_ptr<BrowserSurfaceStateInternal>& state = it->second;
    SurfaceStats stats;
    {
        std::lock_guard<std::mutex> lock(state->frame_mutex);
        stats.exists = true;
        stats.visible = state->visible;
        stats.texture_allocated = state->texture_allocated;
        stats.width = state->width;
        stats.height = state->height;
        stats.paint_count = state->paint_count;
        stats.upload_count = state->upload_count;
        stats.last_upload_frame = state->last_upload_frame;
    }
    return stats;
}

std::vector<std::string> BrowserSystem::list_surface_ids() const
{
    return ordered_ids;
}

void BrowserSystem::tick(std::uint64_t frame_id)
{
    for (const std::string& id : ordered_ids) {
        auto it = surfaces.find(id);
        if (it == surfaces.end()) {
            continue;
        }
        std::shared_ptr<BrowserSurfaceStateInternal> state = it->second;
        if (!state->visible) {
            continue;
        }

        std::uint64_t interval = frame_interval_for(state->max_fps);
        if (frame_id - state->last_upload_frame < interval) {
            continue;
        }

        SurfaceFrame frame;
        {
            std::lock_guard<std::mutex> lock(state->frame_mutex);
            if (!state->pending_frame.dirty) {
                continue;
            }
            frame.width = state->pending_frame.width;
            frame.height = state->pending_frame.height;
            frame.pixels.swap(state->pending_frame.pixels);
            state->pending_frame.dirty = false;
        }

        if (frame.width <= 0 || frame.height <= 0 || frame.pixels.empty()) {
            continue;
        }

        Texture2D& texture = ResourceManager::textures[state->texture_name];
        if (!state->texture_allocated ||
            texture.width != frame.width ||
            texture.height != frame.height ||
            texture.n != 4) {
            texture.allocate(frame.width, frame.height, 4);
            state->texture_allocated = true;
        }
        texture.update_full(frame.pixels.data(), frame.pixels.size());
        state->last_upload_frame = frame_id;
        state->upload_count += 1;
    }
}

} // namespace browser
