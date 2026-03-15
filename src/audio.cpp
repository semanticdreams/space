#include "audio.h"
#include <iostream>
#include <fstream>
#include <cstdint>
#include <cstddef>
#include <memory>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <cctype>
#include <vector>
#include <AL/alext.h>

namespace {
void ensure_openal_drivers() {
    if (std::getenv("ALSOFT_DRIVERS")) {
        return;
    }
#if defined(_WIN32)
    _putenv_s("ALSOFT_DRIVERS", "dsound,wave");
#else
    setenv("ALSOFT_DRIVERS", "pipewire,pulse,alsa", 0);
#endif
}

std::vector<std::string> list_al_devices() {
    const ALCchar* devices = nullptr;
    if (alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_ALL_EXT") == AL_TRUE) {
        devices = alcGetString(nullptr, ALC_ALL_DEVICES_SPECIFIER);
    } else {
        devices = alcGetString(nullptr, ALC_DEVICE_SPECIFIER);
    }
    std::vector<std::string> results;
    if (!devices) {
        return results;
    }
    const ALCchar* ptr = devices;
    while (*ptr) {
        results.emplace_back(ptr);
        ptr += results.back().size() + 1;
    }
    return results;
}

bool contains_case_insensitive(const std::string& haystack, const std::string& needle) {
    auto it = std::search(haystack.begin(), haystack.end(),
                          needle.begin(), needle.end(),
                          [](char a, char b) {
                              return std::tolower(a) == std::tolower(b);
                          });
    return it != haystack.end();
}

std::string pick_preferred_device() {
    const char* env_device = std::getenv("SPACE_AUDIO_DEVICE");
    if (env_device && *env_device) {
        return std::string(env_device);
    }

    const std::vector<std::string> devices = list_al_devices();
#if defined(_WIN32)
    const char* preferred[] = {"dsound", "wave"};
#else
    const char* preferred[] = {"pipewire", "pulse", "alsa"};
#endif
    for (const char* token : preferred) {
        for (const auto& device : devices) {
            if (contains_case_insensitive(device, token)) {
                return device;
            }
        }
    }
    return "";
}

ALCdevice* open_al_device() {
    ensure_openal_drivers();
    std::string preferred = pick_preferred_device();
    if (!preferred.empty()) {
        if (ALCdevice* device = alcOpenDevice(preferred.c_str())) {
            std::cout << "[Audio] Using OpenAL device: " << preferred << std::endl;
            return device;
        }
        std::cerr << "[Audio] Failed to open preferred OpenAL device: " << preferred << std::endl;
    }
    return alcOpenDevice(nullptr);
}
} // namespace

// Basic .wav loader (PCM 16-bit only)
bool loadWavFile(const std::string& filepath,
                 std::unique_ptr<std::uint8_t[]>& outData,
                 std::size_t& outSize,
                 ALenum& format,
                 ALsizei& freq) {
    std::ifstream file(filepath, std::ios::binary);
    if (!file) return false;

    char riff[4];
    file.read(riff, 4);
    if (std::string(riff, 4) != "RIFF") return false;

    file.seekg(8, std::ios::beg);
    char wave[4];
    file.read(wave, 4);
    if (std::string(wave, 4) != "WAVE") return false;

    char fmtChunkId[4];
    file.read(fmtChunkId, 4);
    uint32_t fmtChunkSize;
    file.read(reinterpret_cast<char*>(&fmtChunkSize), 4);

    uint16_t audioFormat, numChannels;
    uint32_t sampleRate, byteRate;
    uint16_t blockAlign, bitsPerSample;

    file.read(reinterpret_cast<char*>(&audioFormat), 2);
    file.read(reinterpret_cast<char*>(&numChannels), 2);
    file.read(reinterpret_cast<char*>(&sampleRate), 4);
    file.read(reinterpret_cast<char*>(&byteRate), 4);
    file.read(reinterpret_cast<char*>(&blockAlign), 2);
    file.read(reinterpret_cast<char*>(&bitsPerSample), 2);

    if (audioFormat != 1) return false; // Not PCM

    // Walk chunks until we find the "data" chunk
    std::string chunkId;
    uint32_t chunkSize = 0;
    while (file.read(reinterpret_cast<char*>(fmtChunkId), 4)) {
        chunkId.assign(fmtChunkId, 4);
        file.read(reinterpret_cast<char*>(&chunkSize), 4);
        if (chunkId == "data") {
            break;
        }
        // Skip unknown chunk payload; chunks are word-aligned
        file.seekg(chunkSize + (chunkSize % 2), std::ios::cur);
    }

    if (chunkId != "data") {
        return false;
    }

    std::unique_ptr<std::uint8_t[]> buffer(new std::uint8_t[chunkSize]);
    file.read(reinterpret_cast<char*>(buffer.get()), chunkSize);
    if (!file) {
        return false;
    }
    outSize = static_cast<std::size_t>(chunkSize);
    outData = std::move(buffer);

    // Determine format
    if (numChannels == 1) {
        format = (bitsPerSample == 8) ? AL_FORMAT_MONO8 : AL_FORMAT_MONO16;
    } else if (numChannels == 2) {
        format = (bitsPerSample == 8) ? AL_FORMAT_STEREO8 : AL_FORMAT_STEREO16;
    } else {
        return false;
    }

    freq = sampleRate;
    return true;
}

Audio::Audio() {
    device = open_al_device();
    if (!device) {
        std::cerr << "Failed to open OpenAL device." << std::endl;
        return;
    }

    context = alcCreateContext(device, nullptr);
    if (!context) {
        std::cerr << "Failed to create OpenAL context." << std::endl;
        alcCloseDevice(device);
        device = nullptr;
        return;
    }

    if (!alcMakeContextCurrent(context)) {
        std::cerr << "Failed to activate OpenAL context." << std::endl;
        alcDestroyContext(context);
        context = nullptr;
        alcCloseDevice(device);
        device = nullptr;
        return;
    }

    applyMasterVolume();
}

Audio::~Audio() {
    std::vector<ALuint> sources = activeSources;
    for (ALuint source : sources) {
        if (streamingSources.find(source) != streamingSources.end()) {
            destroyStreamingSource(source);
        }
    }
    for (auto& pair : buffers) {
        alDeleteBuffers(1, &pair.second);
    }

    for (auto source : activeSources) {
        alDeleteSources(1, &source);
    }

    if (context) {
        alcMakeContextCurrent(nullptr);
        alcDestroyContext(context);
    }

    if (device) {
        alcCloseDevice(device);
    }
}

void Audio::update(uint32_t dt) {
    cleanupStoppedSources();
}

bool Audio::loadSound(const std::string& name, const std::string& filepath) {
    if (buffers.find(name) != buffers.end()) return true; // Already loaded

    std::unique_ptr<std::uint8_t[]> data;
    std::size_t dataSize = 0;
    ALenum format;
    ALsizei freq;

    if (!loadWavFile(filepath, data, dataSize, format, freq)) {
        std::cerr << "Failed to load WAV file: " << filepath << format << freq << std::endl;
        return false;
    }
    //std::cout << "Loaded WAV file: " << filepath << format << " " << freq << std::endl;

    ALuint buffer;
    alGenBuffers(1, &buffer);
    ALenum err = alGetError();
    if (err != AL_NO_ERROR) {
        std::cout << "Error after alGenBuffers: " << alGetString(err) << std::endl;
    }

    auto bufferSize = static_cast<ALsizei>(dataSize);
    bufferSize = bufferSize - bufferSize%4;

    alBufferData(buffer, format, data.get(), bufferSize, freq);
    buffers[name] = buffer;

    err = alGetError();
    if (err != AL_NO_ERROR) {
        std::cout << "OpenAL error: " << alGetString(err) << std::endl;
    }

    return true;
}

ALuint Audio::createBufferFromPcm(const std::string& name,
                                  const std::uint8_t* data,
                                  std::size_t size_bytes,
                                  ALenum format,
                                  ALsizei freq) {
    if (buffers.find(name) != buffers.end()) {
        return buffers[name];
    }

    ALuint buffer = 0;
    alGenBuffers(1, &buffer);
    ALenum err = alGetError();
    if (err != AL_NO_ERROR) {
        std::cerr << "Error after alGenBuffers: " << alGetString(err) << std::endl;
        return 0;
    }

    auto bufferSize = static_cast<ALsizei>(size_bytes);
    alBufferData(buffer, format, data, bufferSize, freq);
    err = alGetError();
    if (err != AL_NO_ERROR) {
        std::cerr << "OpenAL error: " << alGetString(err) << std::endl;
        alDeleteBuffers(1, &buffer);
        return 0;
    }

    buffers[name] = buffer;
    return buffer;
}

bool Audio::isSoundReady(const std::string& name) const {
    return buffers.find(name) != buffers.end();
}

void Audio::unloadSound(const std::string& name) {
    auto it = buffers.find(name);
    if (it != buffers.end()) {
        alDeleteBuffers(1, &it->second);
        buffers.erase(it);
    }
}
ALuint Audio::createSource(ALuint buffer, const glm::vec3& position, bool loop, bool positional) {
    if (!context) {
        return 0;
    }
    ALuint source = 0;
    alGenSources(1, &source);
    ALenum err = alGetError();
    if (err != AL_NO_ERROR || source == 0) {
        return 0;
    }
    alSourcei(source, AL_BUFFER, buffer);
    alSourcef(source, AL_PITCH, 1);
    alSourcef(source, AL_GAIN, 1.0f);
    alSourcei(source, AL_LOOPING, loop ? AL_TRUE : AL_FALSE);

    if (positional) {
        alSourcef(source, AL_MAX_DISTANCE, 300.0f);
        alSourcef(source, AL_ROLLOFF_FACTOR, 0.05f);
        alSourcef(source, AL_REFERENCE_DISTANCE, 10.0f);
        alSource3f(source, AL_POSITION, position.x, position.y, position.z);
        alSource3f(source, AL_VELOCITY, 0.f, 0.f, 0.f);
        alSource3f(source, AL_DIRECTION, 0.f, 0.f, 0.f);
        alSourcei(source, AL_SOURCE_RELATIVE, AL_FALSE);
    } else {
        // Non-positional (e.g., UI sounds): treat source as relative to listener
        alSourcei(source, AL_SOURCE_RELATIVE, AL_TRUE);
        alSource3f(source, AL_POSITION, 0.f, 0.f, 0.f);
    }

    return source;
}

ALuint Audio::createSourceWithoutBuffer(const glm::vec3& position, bool loop, bool positional) {
    if (!context) {
        return 0;
    }
    ALuint source = 0;
    alGenSources(1, &source);
    ALenum err = alGetError();
    if (err != AL_NO_ERROR || source == 0) {
        return 0;
    }
    alSourcef(source, AL_PITCH, 1);
    alSourcef(source, AL_GAIN, 1.0f);
    alSourcei(source, AL_LOOPING, loop ? AL_TRUE : AL_FALSE);

    if (positional) {
        alSourcef(source, AL_MAX_DISTANCE, 300.0f);
        alSourcef(source, AL_ROLLOFF_FACTOR, 0.05f);
        alSourcef(source, AL_REFERENCE_DISTANCE, 10.0f);
        alSource3f(source, AL_POSITION, position.x, position.y, position.z);
        alSource3f(source, AL_VELOCITY, 0.f, 0.f, 0.f);
        alSource3f(source, AL_DIRECTION, 0.f, 0.f, 0.f);
        alSourcei(source, AL_SOURCE_RELATIVE, AL_FALSE);
    } else {
        alSourcei(source, AL_SOURCE_RELATIVE, AL_TRUE);
        alSource3f(source, AL_POSITION, 0.f, 0.f, 0.f);
    }

    return source;
}

void Audio::waitForSoundToFinish(ALuint source) {
    ALint state;
    do {
        alGetSourcei(source, AL_SOURCE_STATE, &state);
        std::this_thread::sleep_for(std::chrono::milliseconds(10)); // small delay to avoid busy-waiting
    } while (state == AL_PLAYING);
}

ALuint Audio::playSound(const std::string& name, const glm::vec3& position, bool loop, bool positional) {
    auto it = buffers.find(name);
    if (it == buffers.end()) {
        std::cerr << "Sound not loaded: " << name << std::endl;
        return 0;
    }

    ALuint source = createSource(it->second, position, loop, positional);
    alSourcePlay(source);
    activeSources.push_back(source);
    return source;
}

void Audio::stopSound(ALuint sourceId) {
    alSourceStop(sourceId);
}

ALuint Audio::createStreamingSource(const glm::vec3& position, bool positional) {
    ALuint source = createSourceWithoutBuffer(position, false, positional);
    if (source == 0) {
        return 0;
    }
    activeSources.push_back(source);
    streamingSources.insert(source);
    {
        std::lock_guard<std::mutex> lock(streamMutex);
        streamQueuedBuffers[source] = {};
    }
    return source;
}

bool Audio::queueStreamPcm16(ALuint sourceId,
                             const std::int16_t* samples,
                             std::size_t sample_count,
                             int channels,
                             int sample_rate,
                             double pts_seconds) {
    if (sourceId == 0 || !samples || sample_count == 0 || sample_rate <= 0) {
        return false;
    }
    if (channels != 1 && channels != 2) {
        return false;
    }
    if (streamingSources.find(sourceId) == streamingSources.end()) {
        return false;
    }

    ALenum format = channels == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16;
    ALuint buffer = 0;
    alGenBuffers(1, &buffer);
    if (buffer == 0) {
        return false;
    }

    const ALsizei bytes = static_cast<ALsizei>(sample_count * sizeof(std::int16_t));
    alBufferData(buffer, format, samples, bytes, static_cast<ALsizei>(sample_rate));
    ALenum err = alGetError();
    if (err != AL_NO_ERROR) {
        alDeleteBuffers(1, &buffer);
        return false;
    }

    alSourceQueueBuffers(sourceId, 1, &buffer);
    err = alGetError();
    if (err != AL_NO_ERROR) {
        alDeleteBuffers(1, &buffer);
        return false;
    }

    const double duration_seconds =
        static_cast<double>(sample_count) / static_cast<double>(std::max(1, channels * sample_rate));
    {
        std::lock_guard<std::mutex> lock(streamMutex);
        auto& queued = streamQueuedBuffers[sourceId];
        double resolved_pts = pts_seconds;
        if (resolved_pts < 0.0 && !queued.empty()) {
            const StreamChunkMeta& tail = queued.back();
            resolved_pts = tail.pts_seconds + tail.duration_seconds;
        }
        StreamChunkMeta chunk;
        chunk.buffer = buffer;
        chunk.duration_seconds = duration_seconds;
        chunk.pts_seconds = resolved_pts;
        queued.push_back(chunk);
    }
    ALint state = AL_STOPPED;
    alGetSourcei(sourceId, AL_SOURCE_STATE, &state);
    if (state != AL_PLAYING) {
        alSourcePlay(sourceId);
    }
    return true;
}

void Audio::reclaimProcessedStreamBuffers(ALuint sourceId) {
    if (streamingSources.find(sourceId) == streamingSources.end()) {
        return;
    }

    ALint processed = 0;
    alGetSourcei(sourceId, AL_BUFFERS_PROCESSED, &processed);
    while (processed-- > 0) {
        ALuint processedBuffer = 0;
        alSourceUnqueueBuffers(sourceId, 1, &processedBuffer);
        if (processedBuffer != 0) {
            alDeleteBuffers(1, &processedBuffer);
            std::lock_guard<std::mutex> lock(streamMutex);
            auto queued_it = streamQueuedBuffers.find(sourceId);
            if (queued_it != streamQueuedBuffers.end()) {
                auto& queued = queued_it->second;
                auto it = std::find_if(
                    queued.begin(), queued.end(),
                    [processedBuffer](const StreamChunkMeta& chunk) { return chunk.buffer == processedBuffer; });
                if (it != queued.end()) {
                    queued.erase(it);
                }
            }
        }
    }
}

void Audio::destroyStreamingSource(ALuint sourceId) {
    if (sourceId == 0) {
        return;
    }
    if (streamingSources.find(sourceId) == streamingSources.end()) {
        return;
    }

    alSourceStop(sourceId);
    reclaimProcessedStreamBuffers(sourceId);

    ALint queuedCount = 0;
    alGetSourcei(sourceId, AL_BUFFERS_QUEUED, &queuedCount);
    while (queuedCount-- > 0) {
        ALuint queuedBuffer = 0;
        alSourceUnqueueBuffers(sourceId, 1, &queuedBuffer);
        if (queuedBuffer != 0) {
            alDeleteBuffers(1, &queuedBuffer);
        }
    }

    {
        std::lock_guard<std::mutex> lock(streamMutex);
        auto queuedIt = streamQueuedBuffers.find(sourceId);
        if (queuedIt != streamQueuedBuffers.end()) {
            queuedIt->second.clear();
            streamQueuedBuffers.erase(queuedIt);
        }
    }

    streamingSources.erase(sourceId);
    auto activeIt = std::find(activeSources.begin(), activeSources.end(), sourceId);
    if (activeIt != activeSources.end()) {
        activeSources.erase(activeIt);
    }
    alDeleteSources(1, &sourceId);
}

void Audio::pauseSource(ALuint sourceId) {
    if (sourceId == 0) {
        return;
    }
    alSourcePause(sourceId);
}

void Audio::playSource(ALuint sourceId) {
    if (sourceId == 0) {
        return;
    }
    alSourcePlay(sourceId);
}

double Audio::getSourceOffsetSeconds(ALuint sourceId) const {
    if (sourceId == 0) {
        return 0.0;
    }
    ALfloat offset = 0.0f;
    alGetSourcef(sourceId, AL_SEC_OFFSET, &offset);
    if (offset < 0.0f) {
        return 0.0;
    }
    return static_cast<double>(offset);
}

double Audio::getStreamingClockSeconds(ALuint sourceId, double fallback_seconds) const {
    if (sourceId == 0) {
        return fallback_seconds;
    }

    ALfloat offset = 0.0f;
    alGetSourcef(sourceId, AL_SEC_OFFSET, &offset);
    const double local_offset = std::max(0.0, static_cast<double>(offset));

    std::lock_guard<std::mutex> lock(streamMutex);
    auto queued_it = streamQueuedBuffers.find(sourceId);
    if (queued_it == streamQueuedBuffers.end() || queued_it->second.empty()) {
        return std::max(0.0, fallback_seconds);
    }

    const StreamChunkMeta& front = queued_it->second.front();
    if (front.pts_seconds >= 0.0) {
        return std::max(0.0, front.pts_seconds + local_offset);
    }

    return std::max(0.0, fallback_seconds + local_offset);
}

void Audio::setListenerPosition(const glm::vec3& position) {
    alListener3f(AL_POSITION, position.x, position.y, position.z);
}

void Audio::setListenerOrientation(const glm::vec3& forward, const glm::vec3& up) {
    float orientation[6] = {
        forward.x, forward.y, forward.z,
        up.x, up.y, up.z
    };
    alListenerfv(AL_ORIENTATION, orientation);
}

void Audio::setListenerVelocity(const glm::vec3& velocity) {
    alListener3f(AL_VELOCITY, velocity.x, velocity.y, velocity.z);
}

void Audio::setSourcePosition(ALuint sourceId, const glm::vec3& position) {
    alSource3f(sourceId, AL_POSITION, position.x, position.y, position.z);
}

void Audio::setSourceVelocity(ALuint sourceId, const glm::vec3& velocity) {
    alSource3f(sourceId, AL_VELOCITY, velocity.x, velocity.y, velocity.z);
}

void Audio::setSourceDirection(ALuint sourceId, const glm::vec3& direction) {
    alSource3f(sourceId, AL_DIRECTION, direction.x, direction.y, direction.z);
}

void Audio::setSourceGain(ALuint sourceId, float gain) {
    alSourcef(sourceId, AL_GAIN, gain);
}

void Audio::setSourcePitch(ALuint sourceId, float pitch) {
    alSourcef(sourceId, AL_PITCH, pitch);
}

void Audio::setSourceMaxDistance(ALuint sourceId, float distance) {
    alSourcef(sourceId, AL_MAX_DISTANCE, distance);
}

void Audio::setSourceRolloffFactor(ALuint sourceId, float factor) {
    alSourcef(sourceId, AL_ROLLOFF_FACTOR, factor);
}

void Audio::setSourceReferenceDistance(ALuint sourceId, float distance) {
    alSourcef(sourceId, AL_REFERENCE_DISTANCE, distance);
}

void Audio::setSourceMinGain(ALuint sourceId, float gain) {
    alSourcef(sourceId, AL_MIN_GAIN, gain);
}

void Audio::setSourceMaxGain(ALuint sourceId, float gain) {
    alSourcef(sourceId, AL_MAX_GAIN, gain);
}

void Audio::setSourceConeInnerAngle(ALuint sourceId, float angle_degrees) {
    alSourcef(sourceId, AL_CONE_INNER_ANGLE, angle_degrees);
}

void Audio::setSourceConeOuterAngle(ALuint sourceId, float angle_degrees) {
    alSourcef(sourceId, AL_CONE_OUTER_ANGLE, angle_degrees);
}

void Audio::setSourceConeOuterGain(ALuint sourceId, float gain) {
    alSourcef(sourceId, AL_CONE_OUTER_GAIN, gain);
}

void Audio::setSourcePositional(ALuint sourceId, bool positional) {
    if (positional) {
        alSourcei(sourceId, AL_SOURCE_RELATIVE, AL_FALSE);
    } else {
        alSourcei(sourceId, AL_SOURCE_RELATIVE, AL_TRUE);
        alSource3f(sourceId, AL_POSITION, 0.f, 0.f, 0.f);
    }
}

void Audio::setMasterVolume(float gain) {
    masterVolume = std::clamp(gain, 0.0f, 1.0f);
    applyMasterVolume();
}

float Audio::getMasterVolume() const {
    return masterVolume;
}

void Audio::cleanupStoppedSources() {
    auto it = activeSources.begin();
    while (it != activeSources.end()) {
        if (streamingSources.find(*it) != streamingSources.end()) {
            reclaimProcessedStreamBuffers(*it);
            ++it;
            continue;
        }
        ALint state;
        alGetSourcei(*it, AL_SOURCE_STATE, &state);
        if (state == AL_STOPPED) {
            alDeleteSources(1, &(*it));
            it = activeSources.erase(it);
        } else {
            ++it;
        }
    }
}

void Audio::reset() {
    // 1. Stop and delete all sources
    std::vector<ALuint> sources = activeSources;
    for (ALuint source : sources) {
        if (streamingSources.find(source) != streamingSources.end()) {
            destroyStreamingSource(source);
        } else {
            alSourceStop(source);
            alDeleteSources(1, &source);
        }
    }
    activeSources.clear();
    streamingSources.clear();
    {
        std::lock_guard<std::mutex> lock(streamMutex);
        streamQueuedBuffers.clear();
    }

    // 2. Delete all buffers (if you plan to reload them)
    for (auto& pair : buffers) {
        alDeleteBuffers(1, &pair.second);
    }
    buffers.clear();

    // 3. Tear down OpenAL context and device
    if (context) {
        alcMakeContextCurrent(nullptr);
        alcDestroyContext(context);
        context = nullptr;
    }

    if (device) {
        alcCloseDevice(device);
        device = nullptr;
    }

    // 4. Reopen the default device
    device = open_al_device();
    if (!device) {
        std::cerr << "Failed to reopen OpenAL device." << std::endl;
        return;
    }

    context = alcCreateContext(device, nullptr);
    if (!context || !alcMakeContextCurrent(context)) {
        std::cerr << "Failed to recreate OpenAL context." << std::endl;
        return;
    }

    applyMasterVolume();
    std::cout << "[Audio] OpenAL reset completed.\n";
}

void Audio::applyMasterVolume() {
    alListenerf(AL_GAIN, masterVolume);
}
