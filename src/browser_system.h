#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace browser {

struct BrowserSurfaceStateInternal;

struct SurfaceConfig {
    std::string id;
    std::string url;
    std::string texture_name;
    std::uint32_t width { 1024 };
    std::uint32_t height { 1024 };
    std::uint32_t max_fps { 30 };
};

// BrowserSystem is a production-oriented coordination layer between scene surfaces and browser instances.
// Rendering and input routing hooks are intentionally explicit so any mesh/face can host a web surface.
class BrowserSystem {
public:
    struct SurfaceStats {
        bool exists { false };
        bool visible { false };
        bool texture_allocated { false };
        std::uint32_t width { 0 };
        std::uint32_t height { 0 };
        std::uint64_t paint_count { 0 };
        std::uint64_t upload_count { 0 };
        std::uint64_t last_upload_frame { 0 };
    };

    bool create_surface(const SurfaceConfig& config);
    bool destroy_surface(const std::string& id);
    void shutdown();
    bool set_surface_url(const std::string& id, const std::string& url);
    void set_surface_visible(const std::string& id, bool visible);
    bool set_surface_focus(const std::string& id, bool focused);
    bool send_mouse_move(const std::string& id, int x, int y, bool mouse_leave = false);
    bool send_mouse_click(const std::string& id, int x, int y, int button, bool mouse_up, int click_count);
    bool send_mouse_wheel(const std::string& id, int x, int y, int delta_x, int delta_y);
    std::optional<std::string> get_surface_texture_name(const std::string& id) const;
    std::optional<SurfaceStats> get_surface_stats(const std::string& id) const;
    std::vector<std::string> list_surface_ids() const;
    void tick(std::uint64_t frame_id);

private:
    std::unordered_map<std::string, std::shared_ptr<BrowserSurfaceStateInternal>> surfaces;
    std::vector<std::string> ordered_ids;
};

} // namespace browser
