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
    _putenv_s("ALSOFT_DRIVERS", "pulse,alsa");
#else
    setenv("ALSOFT_DRIVERS", "pulse,alsa", 0);
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
    const char* preferred[] = {"pulse", "pipewire", "alsa"};
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
    if (!context || !alcMakeContextCurrent(context)) {
        std::cerr << "Failed to create or activate OpenAL context." << std::endl;
        return;
    }

    applyMasterVolume();
}

Audio::~Audio() {
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
    ALuint source;
    alGenSources(1, &source);
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
    for (auto& source : activeSources) {
        alSourceStop(source);
        alDeleteSources(1, &source);
    }
    activeSources.clear();

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
