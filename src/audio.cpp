#include "audio.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <thread>
#include <chrono>
#include <AL/alext.h>

// Basic .wav loader (PCM 16-bit only)
bool loadWavFile(const std::string& filepath, std::vector<char>& outData, ALenum& format, ALsizei& freq) {
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

    file.seekg(20 + fmtChunkSize + 8, std::ios::beg); // Skip to data
    char dataId[4];
    file.read(dataId, 4);
    uint32_t dataSize;
    file.read(reinterpret_cast<char*>(&dataSize), 4);

    outData.resize(dataSize);
    file.read(outData.data(), dataSize);

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
    device = alcOpenDevice(nullptr);
    if (!device) {
        std::cerr << "Failed to open OpenAL device." << std::endl;
        return;
    }

    context = alcCreateContext(device, nullptr);
    if (!context || !alcMakeContextCurrent(context)) {
        std::cerr << "Failed to create or activate OpenAL context." << std::endl;
        return;
    }
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

    std::vector<char> data;
    ALenum format;
    ALsizei freq;

    if (!loadWavFile(filepath, data, format, freq)) {
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

    auto bufferSize = static_cast<ALsizei>(data.size());
    bufferSize = bufferSize - bufferSize%4;

    alBufferData(buffer, format, data.data(), bufferSize, freq);
    buffers[name] = buffer;

    err = alGetError();
    if (err != AL_NO_ERROR) {
        std::cout << "OpenAL error: " << alGetString(err) << std::endl;
    }

    return true;
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
    device = alcOpenDevice(nullptr);
    if (!device) {
        std::cerr << "Failed to reopen OpenAL device." << std::endl;
        return;
    }

    context = alcCreateContext(device, nullptr);
    if (!context || !alcMakeContextCurrent(context)) {
        std::cerr << "Failed to recreate OpenAL context." << std::endl;
        return;
    }

    std::cout << "[Audio] OpenAL reset completed.\n";
}
