#include <algorithm>
#include <stdexcept>
#include <sol/sol.hpp>

#include "audio_input.h"

namespace {

AudioInput::Config parse_config(const sol::object& options)
{
    AudioInput::Config config;
    if (!options.valid() || options.get_type() != sol::type::table) {
        return config;
    }
    sol::table table = options;
    sol::optional<double> sample_rate = table["sample-rate"];
    if (sample_rate) {
        config.sampleRate = *sample_rate;
    }
    sol::optional<int> channels = table["channels"];
    if (channels) {
        config.channels = *channels;
    }
    sol::optional<unsigned long> frames_per_buffer = table["frames-per-buffer"];
    if (frames_per_buffer) {
        config.framesPerBuffer = *frames_per_buffer;
    }
    sol::optional<int> device_index = table["device"];
    if (device_index) {
        config.deviceIndex = *device_index;
    }
    sol::optional<std::size_t> buffer_frames = table["buffer-frames"];
    sol::optional<double> buffer_seconds = table["buffer-seconds"];
    if (buffer_frames) {
        config.bufferFrames = *buffer_frames;
    } else if (buffer_seconds) {
        double seconds = std::max(0.0, *buffer_seconds);
        config.bufferFrames = static_cast<std::size_t>(config.sampleRate * seconds);
    }
    return config;
}

sol::table create_audio_input_table(sol::state_view lua)
{
    sol::table audio_table = lua.create_table();

    audio_table.new_usertype<AudioInput>("AudioInput",
        sol::no_constructor,
        "start", &AudioInput::start,
        "stop", &AudioInput::stop,
        "running?", &AudioInput::isRunning,
        "channels", &AudioInput::channels,
        "sample-rate", &AudioInput::sampleRate,
        "available-frames", &AudioInput::availableFrames,
        "read-frames", &AudioInput::readFrames,
        "read-frames-into", [](AudioInput& self, void* buffer, std::size_t max_frames) {
            if (buffer == nullptr) {
                throw std::runtime_error("AudioInput.read-frames-into requires a valid buffer pointer");
            }
            return self.readFramesInto(static_cast<float*>(buffer), max_frames);
        },
        "clear", &AudioInput::clear,
        "dropped-samples", &AudioInput::droppedSamples,
        "overflow-count", &AudioInput::overflowCount);

    audio_table.set_function("AudioInput", [](sol::object options) {
        AudioInput::Config config = parse_config(options);
        return std::make_unique<AudioInput>(config);
    });

    audio_table.set_function("list-devices", [lua]() mutable {
        std::vector<AudioInputDeviceInfo> devices = list_audio_input_devices();
        sol::table out = lua.create_table(static_cast<int>(devices.size()), 0);
        int index = 1;
        for (const auto& device : devices) {
            sol::table entry = lua.create_table();
            entry["index"] = device.index;
            entry["name"] = device.name;
            entry["max-input-channels"] = device.maxInputChannels;
            entry["default-sample-rate"] = device.defaultSampleRate;
            entry["host-api"] = device.hostApi;
            entry["default-low-input-latency"] = device.defaultLowInputLatency;
            entry["default-high-input-latency"] = device.defaultHighInputLatency;
            out[index++] = entry;
        }
        return out;
    });

    audio_table.set_function("default-input-device", [lua]() mutable -> sol::object {
        std::optional<int> device = default_audio_input_device();
        if (!device) {
            return sol::make_object(lua, sol::lua_nil);
        }
        return sol::make_object(lua, device.value());
    });

    return audio_table;
}

} // namespace

void lua_bind_audio_input(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("audio-input", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_audio_input_table(lua);
    });
}
