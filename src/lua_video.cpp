#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>

#include <sol/sol.hpp>

#include "lua_video.h"
#include "texture.h"
#include "video_player.h"

namespace {

VideoManager g_lua_fallback_video_manager;
constexpr const char* k_video_manager_registry_key = "__space_video_manager_ptr";

VideoManager* manager_from_registry(sol::state_view lua)
{
    sol::table registry = lua.registry();
    sol::optional<VideoManager*> manager_opt = registry[k_video_manager_registry_key];
    if (manager_opt) {
        return *manager_opt;
    }
    return nullptr;
}

VideoPlayer::Options parse_options(const sol::object& options_obj, std::string& path)
{
    VideoPlayer::Options parsed;
    if (!options_obj.valid() || options_obj.get_type() != sol::type::table) {
        throw std::runtime_error("video.VideoPlayer requires an options table");
    }

    sol::table table = options_obj.as<sol::table>();
    sol::optional<std::string> path_opt = table["path"];
    if (!path_opt || path_opt->empty()) {
        throw std::runtime_error("video.VideoPlayer requires a non-empty :path");
    }
    path = *path_opt;

    sol::optional<bool> loop = table["loop"];
    sol::optional<bool> autoplay = table["autoplay"];
    sol::optional<bool> muted = table["muted"];
    if (loop) {
        parsed.loop = *loop;
    }
    if (autoplay) {
        parsed.autoplay = *autoplay;
    }
    if (muted) {
        parsed.muted = *muted;
    }

    return parsed;
}

sol::table create_video_table(sol::state_view lua)
{
    sol::table video_table = lua.create_table();

#if defined(SPACE_HAS_FFMPEG)
    video_table["available"] = true;
    video_table.new_usertype<VideoPlayer>("VideoPlayer",
        sol::no_constructor,
        "play", &VideoPlayer::play,
        "pause", &VideoPlayer::pause,
        "stop", &VideoPlayer::stop,
        "seek", &VideoPlayer::seek,
        "update", &VideoPlayer::update,
        "drop", &VideoPlayer::drop,
        "ready", &VideoPlayer::ready,
        "ended", &VideoPlayer::ended,
        "playing", &VideoPlayer::playing,
        "status", [](VideoPlayer& player, sol::this_state state) {
            sol::state_view lua(state);
            sol::table status = lua.create_table();
            std::string error = player.last_error();
            status["ready"] = player.ready();
            status["ended"] = player.ended();
            status["playing"] = player.playing();
            status["error"] = error;
            status["has-error"] = !error.empty();
            status["clock-seconds"] = player.last_clock_seconds();
            status["has-audio-clock"] = player.has_audio_clock();
            status["audio-available"] = player.audio_available();
            status["audio-active"] = player.audio_active();
            status["queued-audio-chunks"] = static_cast<std::int64_t>(player.queued_audio_chunks());
            status["dropped-audio-chunks"] = static_cast<std::int64_t>(player.dropped_audio_chunks());
            status["flushed-audio-chunks"] = static_cast<std::int64_t>(player.flushed_audio_chunks());
            status["av-drift-seconds"] = player.last_av_drift_seconds();
            status["max-av-drift-seconds"] = player.max_av_drift_seconds();
            status["recent-max-av-drift-seconds"] = player.recent_max_av_drift_seconds();
            status["av-drift-window-seconds"] = player.recent_av_drift_window_seconds();
            status["dropped-video-frames"] = player.dropped_video_frames();
            status["decode-loop-iterations"] = static_cast<std::int64_t>(player.decode_loop_iterations());
            status["decode-wait-ms"] = static_cast<std::int64_t>(player.decode_wait_milliseconds());
            return status;
        },
        "duration", &VideoPlayer::duration,
        "position", &VideoPlayer::position,
        "last_error", &VideoPlayer::last_error,
        "texture", &VideoPlayer::texture
    );

    video_table.set_function("VideoPlayer", [](sol::object options_obj) {
        sol::state_view lua(options_obj.lua_state());
        std::string path;
        VideoPlayer::Options options = parse_options(options_obj, path);
        VideoManager* manager = lua_video_get_manager(lua);
        if (!manager) {
            manager = &g_lua_fallback_video_manager;
        }
        return std::make_unique<VideoPlayer>(*manager, path, options);
    });
#else
    video_table["available"] = false;
    video_table["missing-reason"] = "video module built without FFmpeg support";
    video_table.set_function("VideoPlayer", [](sol::object) -> std::unique_ptr<VideoPlayer> {
        throw std::runtime_error("video module unavailable: build with SPACE_ENABLE_FFMPEG and install FFmpeg dev packages");
    });
#endif

    return video_table;
}

} // namespace

void lua_bind_video(sol::state& lua)
{
    lua_video_set_manager(lua, nullptr);
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("video", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_video_table(lua);
    });
}

void lua_video_set_manager(sol::state& lua, VideoManager* manager)
{
    sol::table registry = lua.registry();
    registry[k_video_manager_registry_key] = manager;
}

VideoManager* lua_video_get_manager(sol::state_view lua)
{
    return manager_from_registry(lua);
}

void lua_video_notify_audio_reset(sol::state_view lua, Audio* previous_audio)
{
    VideoManager* manager = lua_video_get_manager(lua);
    if (!manager) {
        manager = &g_lua_fallback_video_manager;
    }
    manager->on_audio_reset(previous_audio);
}
