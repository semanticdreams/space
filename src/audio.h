#pragma once

#include <cstdint>
#include <cstddef>
#include <algorithm>
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
    ALuint createBufferFromPcm(const std::string& name,
                               const std::uint8_t* data,
                               std::size_t size_bytes,
                               ALenum format,
                               ALsizei freq);
    bool isSoundReady(const std::string& name) const;

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

    void setMasterVolume(float gain);
    float getMasterVolume() const;

    void reset();

private:
    ALCdevice* device;
    ALCcontext* context;

    std::unordered_map<std::string, ALuint> buffers;
    std::vector<ALuint> activeSources;
    float masterVolume = 1.0f;

    ALuint createSource(ALuint buffer, const glm::vec3& position, bool loop, bool positional);
    void cleanupStoppedSources();
    void applyMasterVolume();
};
