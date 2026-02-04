#include <glm/vec3.hpp>
#include <optional>
#include <sol/sol.hpp>
#include <string>
#include <utility>

#include "audio.h"
#include "lua_callbacks.h"
#include "resource_manager.h"

namespace {

sol::table create_audio_table(sol::state_view lua)
{
    sol::table audio_table = lua.create_table();
    audio_table.new_usertype<Audio>("Audio",
        sol::no_constructor,
        "loadSound", &Audio::loadSound,
        "loadSoundAsync", [](Audio& self, const std::string& name, const std::string& path, sol::object cb) {
            (void) self;
            std::optional<uint64_t> cb_id;
            if (cb.is<sol::function>()) {
                sol::function fn = cb.as<sol::function>();
                cb_id = lua_callbacks_register(fn);
            }
            ResourceManager::ReadyCallback onReady = [cb_id](const std::string&) {
                if (cb_id) {
                    lua_callbacks_enqueue_value(cb_id.value(), sol::lua_nil);
                }
            };
            return ResourceManager::loadAudioAsync(name, path, std::move(onReady));
        },
        "unloadSound", &Audio::unloadSound,
        "playSound", sol::overload(
            [](Audio& self, const std::string& name, const glm::vec3& position) {
                return self.playSound(name, position, false, true);
            },
            [](Audio& self, const std::string& name, const glm::vec3& position, bool loop) {
                return self.playSound(name, position, loop, true);
            },
            [](Audio& self, const std::string& name, const glm::vec3& position, bool loop, bool positional) {
                return self.playSound(name, position, loop, positional);
            }),
        "stopSound", &Audio::stopSound,
        "waitForSoundToFinish", &Audio::waitForSoundToFinish,
        "isReady", &Audio::isSoundReady,
        "setListenerPosition", &Audio::setListenerPosition,
        "setListenerOrientation", &Audio::setListenerOrientation,
        "setListenerVelocity", &Audio::setListenerVelocity,
        "setSourcePosition", &Audio::setSourcePosition,
        "setSourceVelocity", &Audio::setSourceVelocity,
        "setMasterVolume", &Audio::setMasterVolume,
        "getMasterVolume", &Audio::getMasterVolume,
        "reset", &Audio::reset,
        "update", &Audio::update);
    return audio_table;
}

} // namespace

void lua_bind_audio(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("audio", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_audio_table(lua);
    });
}
