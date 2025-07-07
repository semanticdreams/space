#pragma once

#include <cstdint>
#include <unordered_map>
#include <string>
#include <vector>
#include <AL/al.h>
#include <AL/alc.h>
#include <glm/vec3.hpp>

class Audio {
public:
    Audio();
    ~Audio();

    void update(uint32_t); // For streaming or timed cleanup

    // Sound loading and management
    bool loadSound(const std::string& name, const std::string& filepath);
    void unloadSound(const std::string& name);

    // Playback
    ALuint playSound(const std::string& name, const glm::vec3& position, bool loop = false, bool positional = true);
    void stopSound(ALuint sourceId);
    void waitForSoundToFinish(ALuint);

    // Listener properties
    void setListenerPosition(const glm::vec3& position);
    void setListenerOrientation(const glm::vec3& forward, const glm::vec3& up);
    void setListenerVelocity(const glm::vec3& velocity);

    // Source manipulation
    void setSourcePosition(ALuint sourceId, const glm::vec3& position);
    void setSourceVelocity(ALuint sourceId, const glm::vec3& velocity);

    void reset();

private:
    ALCdevice* device;
    ALCcontext* context;

    std::unordered_map<std::string, ALuint> buffers;
    std::vector<ALuint> activeSources;

    ALuint createSource(ALuint buffer, const glm::vec3& position, bool loop, bool positional);
    void cleanupStoppedSources();
};

