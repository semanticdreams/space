#pragma once

#include <cstdint>
#include <cstddef>
#include <algorithm>
#include <deque>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
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
    ALuint createStreamingSource(const glm::vec3& position, bool positional = true);
    bool queueStreamPcm16(ALuint sourceId,
                          const std::int16_t* samples,
                          std::size_t sample_count,
                          int channels,
                          int sample_rate,
                          double pts_seconds = -1.0);
    void reclaimProcessedStreamBuffers(ALuint sourceId);
    void destroyStreamingSource(ALuint sourceId);
    void pauseSource(ALuint sourceId);
    void playSource(ALuint sourceId);
    double getSourceOffsetSeconds(ALuint sourceId) const;
    double getStreamingClockSeconds(ALuint sourceId, double fallback_seconds) const;

    // Listener properties
    void setListenerPosition(const glm::vec3& position);
    void setListenerOrientation(const glm::vec3& forward, const glm::vec3& up);
    void setListenerVelocity(const glm::vec3& velocity);

    // Source manipulation
    void setSourcePosition(ALuint sourceId, const glm::vec3& position);
    void setSourceVelocity(ALuint sourceId, const glm::vec3& velocity);
    void setSourceDirection(ALuint sourceId, const glm::vec3& direction);
    void setSourceGain(ALuint sourceId, float gain);
    void setSourcePitch(ALuint sourceId, float pitch);
    void setSourceMaxDistance(ALuint sourceId, float distance);
    void setSourceRolloffFactor(ALuint sourceId, float factor);
    void setSourceReferenceDistance(ALuint sourceId, float distance);
    void setSourceMinGain(ALuint sourceId, float gain);
    void setSourceMaxGain(ALuint sourceId, float gain);
    void setSourceConeInnerAngle(ALuint sourceId, float angle_degrees);
    void setSourceConeOuterAngle(ALuint sourceId, float angle_degrees);
    void setSourceConeOuterGain(ALuint sourceId, float gain);
    void setSourcePositional(ALuint sourceId, bool positional);

    void setMasterVolume(float gain);
    float getMasterVolume() const;

    void reset();

private:
    ALCdevice* device { nullptr };
    ALCcontext* context { nullptr };

    std::unordered_map<std::string, ALuint> buffers;
    std::vector<ALuint> activeSources;
    std::unordered_set<ALuint> streamingSources;
    struct StreamChunkMeta {
        ALuint buffer { 0 };
        double duration_seconds { 0.0 };
        double pts_seconds { -1.0 };
    };
    mutable std::mutex streamMutex;
    std::unordered_map<ALuint, std::deque<StreamChunkMeta>> streamQueuedBuffers;
    float masterVolume = 1.0f;

    ALuint createSource(ALuint buffer, const glm::vec3& position, bool loop, bool positional);
    ALuint createSourceWithoutBuffer(const glm::vec3& position, bool loop, bool positional);
    void cleanupStoppedSources();
    void applyMasterVolume();
};
