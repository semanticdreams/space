#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

struct AudioInputDeviceInfo {
    int index = -1;
    std::string name;
    int maxInputChannels = 0;
    double defaultSampleRate = 0.0;
    std::string hostApi;
    double defaultLowInputLatency = 0.0;
    double defaultHighInputLatency = 0.0;
};

std::vector<AudioInputDeviceInfo> list_audio_input_devices();
std::optional<int> default_audio_input_device();

class AudioInput {
public:
    struct Config {
        double sampleRate = 48000.0;
        int channels = 1;
        unsigned long framesPerBuffer = 256;
        std::size_t bufferFrames = 0;
        int deviceIndex = -1;
    };

    explicit AudioInput(const Config& config);
    ~AudioInput();

    AudioInput(const AudioInput&) = delete;
    AudioInput& operator=(const AudioInput&) = delete;
    AudioInput(AudioInput&&) noexcept;
    AudioInput& operator=(AudioInput&&) noexcept;

    bool start();
    void stop();
    bool isRunning() const;
    int channels() const;
    double sampleRate() const;
    std::size_t availableFrames() const;
    std::vector<float> readFrames(std::size_t maxFrames);
    std::size_t readFramesInto(float* out, std::size_t maxFrames);
    void clear();
    std::uint64_t droppedSamples() const;
    std::uint64_t overflowCount() const;

private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
