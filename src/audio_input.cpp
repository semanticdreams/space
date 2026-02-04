#include "audio_input.h"

#include <algorithm>
#include <atomic>
#include <mutex>
#include <stdexcept>

#include <portaudio.h>

namespace {

class PortAudioScope {
public:
    PortAudioScope()
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (refcount == 0) {
            PaError err = Pa_Initialize();
            if (err != paNoError) {
                throw std::runtime_error(Pa_GetErrorText(err));
            }
        }
        refcount++;
    }

    ~PortAudioScope()
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (refcount == 0) {
            return;
        }
        refcount--;
        if (refcount == 0) {
            Pa_Terminate();
        }
    }

    PortAudioScope(const PortAudioScope&) = delete;
    PortAudioScope& operator=(const PortAudioScope&) = delete;

private:
    static std::mutex mutex;
    static int refcount;
};

std::mutex PortAudioScope::mutex;
int PortAudioScope::refcount = 0;

class SampleRingBuffer {
public:
    explicit SampleRingBuffer(std::size_t capacity)
        : data(capacity)
    {
    }

    void push(const float* samples, std::size_t count)
    {
        if (count == 0 || data.empty()) {
            return;
        }
        std::unique_lock<std::mutex> lock(mutex, std::try_to_lock);
        if (!lock.owns_lock()) {
            droppedSamples.fetch_add(count, std::memory_order_relaxed);
            return;
        }
        if (count >= data.size()) {
            samples += count - data.size();
            count = data.size();
            head = 0;
            size = 0;
        }
        for (std::size_t i = 0; i < count; ++i) {
            if (size < data.size()) {
                std::size_t index = (head + size) % data.size();
                data[index] = samples[i];
                size++;
            } else {
                data[head] = samples[i];
                head = (head + 1) % data.size();
                droppedSamples.fetch_add(1, std::memory_order_relaxed);
            }
        }
    }

    std::vector<float> read(std::size_t maxSamples)
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (maxSamples == 0 || size == 0) {
            return {};
        }
        std::size_t count = std::min(maxSamples, size);
        std::vector<float> out;
        out.reserve(count);
        for (std::size_t i = 0; i < count; ++i) {
            out.push_back(data[(head + i) % data.size()]);
        }
        head = (head + count) % data.size();
        size -= count;
        return out;
    }

    std::size_t read_into(float* out, std::size_t maxSamples)
    {
        if (!out) {
            return 0;
        }
        std::lock_guard<std::mutex> lock(mutex);
        if (maxSamples == 0 || size == 0) {
            return 0;
        }
        std::size_t count = std::min(maxSamples, size);
        for (std::size_t i = 0; i < count; ++i) {
            out[i] = data[(head + i) % data.size()];
        }
        head = (head + count) % data.size();
        size -= count;
        return count;
    }

    std::size_t available() const
    {
        std::lock_guard<std::mutex> lock(mutex);
        return size;
    }

    void clear()
    {
        std::lock_guard<std::mutex> lock(mutex);
        head = 0;
        size = 0;
    }

    std::uint64_t dropped() const
    {
        return droppedSamples.load(std::memory_order_relaxed);
    }

private:
    mutable std::mutex mutex;
    std::vector<float> data;
    std::size_t head = 0;
    std::size_t size = 0;
    std::atomic<std::uint64_t> droppedSamples { 0 };
};

} // namespace

struct AudioInput::Impl {
    explicit Impl(const AudioInput::Config& config)
        : runtime()
        , config(config)
        , ring(normalize_buffer_frames(config))
    {
        validate_config();
        open_stream();
    }

    ~Impl()
    {
        stop_stream();
        close_stream();
    }

    Impl(const Impl&) = delete;
    Impl& operator=(const Impl&) = delete;

    PortAudioScope runtime;
    AudioInput::Config config;
    SampleRingBuffer ring;
    PaStream* stream = nullptr;
    std::atomic<bool> running { false };
    std::atomic<std::uint64_t> overflowCount { 0 };

    static std::size_t normalize_buffer_frames(const AudioInput::Config& config)
    {
        if (config.bufferFrames > 0) {
            return config.bufferFrames * static_cast<std::size_t>(std::max(1, config.channels));
        }
        double seconds = 2.0;
        return static_cast<std::size_t>(config.sampleRate * seconds) * static_cast<std::size_t>(std::max(1, config.channels));
    }

    void validate_config() const
    {
        if (config.sampleRate <= 0.0) {
            throw std::runtime_error("AudioInput sampleRate must be > 0");
        }
        if (config.channels <= 0) {
            throw std::runtime_error("AudioInput channels must be > 0");
        }
    }

    void open_stream()
    {
        PaStreamParameters input_params;
        input_params.device = (config.deviceIndex >= 0) ? config.deviceIndex : Pa_GetDefaultInputDevice();
        if (input_params.device == paNoDevice) {
            throw std::runtime_error("PortAudio: no default input device available");
        }
        const PaDeviceInfo* device_info = Pa_GetDeviceInfo(input_params.device);
        if (!device_info) {
            throw std::runtime_error("PortAudio: failed to read device info");
        }
        if (config.channels > device_info->maxInputChannels) {
            throw std::runtime_error("PortAudio: requested channels exceed device input channels");
        }
        input_params.channelCount = config.channels;
        input_params.sampleFormat = paFloat32;
        input_params.suggestedLatency = device_info->defaultLowInputLatency;
        input_params.hostApiSpecificStreamInfo = nullptr;

        PaError err = Pa_OpenStream(&stream,
            &input_params,
            nullptr,
            config.sampleRate,
            config.framesPerBuffer,
            paNoFlag,
            &Impl::pa_callback,
            this);
        if (err != paNoError) {
            throw std::runtime_error(Pa_GetErrorText(err));
        }
    }

    void close_stream()
    {
        if (!stream) {
            return;
        }
        Pa_CloseStream(stream);
        stream = nullptr;
    }

    void stop_stream()
    {
        if (!stream) {
            return;
        }
        if (running.load(std::memory_order_relaxed)) {
            Pa_StopStream(stream);
            running.store(false, std::memory_order_relaxed);
        }
    }

    static int pa_callback(const void* input,
        void* output,
        unsigned long frame_count,
        const PaStreamCallbackTimeInfo* time_info,
        PaStreamCallbackFlags status_flags,
        void* user_data)
    {
        (void) output;
        (void) time_info;
        auto* self = static_cast<Impl*>(user_data);
        if (status_flags & paInputOverflow) {
            self->overflowCount.fetch_add(1, std::memory_order_relaxed);
        }
        if (!input || frame_count == 0) {
            return paContinue;
        }
        const float* samples = static_cast<const float*>(input);
        std::size_t sample_count = frame_count * static_cast<std::size_t>(self->config.channels);
        self->ring.push(samples, sample_count);
        return paContinue;
    }
};

std::vector<AudioInputDeviceInfo> list_audio_input_devices()
{
    PortAudioScope scope;
    PaError count = Pa_GetDeviceCount();
    if (count < 0) {
        throw std::runtime_error(Pa_GetErrorText(count));
    }
    std::vector<AudioInputDeviceInfo> devices;
    devices.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) {
        const PaDeviceInfo* info = Pa_GetDeviceInfo(i);
        if (!info) {
            continue;
        }
        const PaHostApiInfo* host = Pa_GetHostApiInfo(info->hostApi);
        AudioInputDeviceInfo device;
        device.index = i;
        device.name = info->name ? info->name : "";
        device.maxInputChannels = info->maxInputChannels;
        device.defaultSampleRate = info->defaultSampleRate;
        device.hostApi = host && host->name ? host->name : "";
        device.defaultLowInputLatency = info->defaultLowInputLatency;
        device.defaultHighInputLatency = info->defaultHighInputLatency;
        devices.push_back(std::move(device));
    }
    return devices;
}

std::optional<int> default_audio_input_device()
{
    PortAudioScope scope;
    PaDeviceIndex device = Pa_GetDefaultInputDevice();
    if (device == paNoDevice) {
        return std::nullopt;
    }
    return static_cast<int>(device);
}

AudioInput::AudioInput(const Config& config)
    : impl(std::make_unique<Impl>(config))
{
}

AudioInput::~AudioInput() = default;

AudioInput::AudioInput(AudioInput&&) noexcept = default;
AudioInput& AudioInput::operator=(AudioInput&&) noexcept = default;

bool AudioInput::start()
{
    if (!impl || !impl->stream) {
        return false;
    }
    if (impl->running.load(std::memory_order_relaxed)) {
        return true;
    }
    PaError err = Pa_StartStream(impl->stream);
    if (err != paNoError) {
        throw std::runtime_error(Pa_GetErrorText(err));
    }
    impl->running.store(true, std::memory_order_relaxed);
    return true;
}

void AudioInput::stop()
{
    if (!impl) {
        return;
    }
    impl->stop_stream();
}

bool AudioInput::isRunning() const
{
    if (!impl) {
        return false;
    }
    return impl->running.load(std::memory_order_relaxed);
}

int AudioInput::channels() const
{
    return impl ? impl->config.channels : 0;
}

double AudioInput::sampleRate() const
{
    return impl ? impl->config.sampleRate : 0.0;
}

std::size_t AudioInput::availableFrames() const
{
    if (!impl || impl->config.channels <= 0) {
        return 0;
    }
    std::size_t samples = impl->ring.available();
    return samples / static_cast<std::size_t>(impl->config.channels);
}

std::vector<float> AudioInput::readFrames(std::size_t maxFrames)
{
    if (!impl || impl->config.channels <= 0 || maxFrames == 0) {
        return {};
    }
    std::size_t maxSamples = maxFrames * static_cast<std::size_t>(impl->config.channels);
    return impl->ring.read(maxSamples);
}

std::size_t AudioInput::readFramesInto(float* out, std::size_t maxFrames)
{
    if (!impl || impl->config.channels <= 0 || maxFrames == 0 || !out) {
        return 0;
    }
    std::size_t maxSamples = maxFrames * static_cast<std::size_t>(impl->config.channels);
    std::size_t read = impl->ring.read_into(out, maxSamples);
    return read / static_cast<std::size_t>(impl->config.channels);
}

void AudioInput::clear()
{
    if (!impl) {
        return;
    }
    impl->ring.clear();
}

std::uint64_t AudioInput::droppedSamples() const
{
    return impl ? impl->ring.dropped() : 0;
}

std::uint64_t AudioInput::overflowCount() const
{
    return impl ? impl->overflowCount.load(std::memory_order_relaxed) : 0;
}
