#pragma once

#include <sol/sol.hpp>

class Audio;
class VideoManager;

void lua_bind_video(sol::state& lua);
void lua_video_set_manager(sol::state& lua, VideoManager* manager);
VideoManager* lua_video_get_manager(sol::state_view lua);
void lua_video_notify_audio_reset(sol::state_view lua, Audio* previous_audio);
