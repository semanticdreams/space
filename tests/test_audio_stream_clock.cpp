#include "audio.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <thread>
#include <vector>

namespace {

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

void fill_sine(std::vector<std::int16_t>& out, int channels, int sample_rate, double frequency_hz, double phase_offset)
{
    const double two_pi = 6.283185307179586;
    const int frame_count = static_cast<int>(out.size()) / channels;
    for (int frame = 0; frame < frame_count; ++frame) {
        double t = static_cast<double>(frame) / static_cast<double>(sample_rate);
        double sample = std::sin(two_pi * frequency_hz * (t + phase_offset));
        std::int16_t pcm = static_cast<std::int16_t>(std::clamp(sample * 12000.0, -32768.0, 32767.0));
        for (int ch = 0; ch < channels; ++ch) {
            out[static_cast<std::size_t>(frame * channels + ch)] = pcm;
        }
    }
}

} // namespace

int main()
{
    constexpr int channels = 2;
    constexpr int sample_rate = 48000;
    constexpr int chunk_frames = 480; // 10ms
    const double chunk_seconds = static_cast<double>(chunk_frames) / static_cast<double>(sample_rate);

    Audio audio;
    ALuint source = audio.createStreamingSource(glm::vec3(0.0f), false);
    if (source == 0) {
        std::cout << "SKIP: no streaming audio source available (likely no OpenAL device)\n";
        return 0;
    }

    std::vector<std::int16_t> pcm(static_cast<std::size_t>(chunk_frames * channels));
    double pts_seconds = 0.0;
    double last_clock = 0.0;

    for (int i = 0; i < 220; ++i) {
        fill_sine(pcm, channels, sample_rate, 220.0, pts_seconds);
        bool queued =
            audio.queueStreamPcm16(source, pcm.data(), pcm.size(), channels, sample_rate, pts_seconds);
        if (!check(queued, "queueStreamPcm16 should succeed")) {
            audio.destroyStreamingSource(source);
            return 1;
        }

        if ((i % 3) == 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(4));
        }

        audio.reclaimProcessedStreamBuffers(source);
        double now_clock = audio.getStreamingClockSeconds(source, last_clock);
        if (!check(now_clock + 1e-6 >= last_clock, "streaming clock regressed during churn")) {
            std::cerr << "last=" << last_clock << " now=" << now_clock << "\n";
            audio.destroyStreamingSource(source);
            return 1;
        }
        last_clock = std::max(last_clock, now_clock);
        pts_seconds += chunk_seconds;
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    for (int i = 0; i < 8; ++i) {
        audio.reclaimProcessedStreamBuffers(source);
        double now_clock = audio.getStreamingClockSeconds(source, last_clock);
        if (!check(now_clock + 1e-6 >= last_clock, "streaming clock regressed while draining")) {
            std::cerr << "last=" << last_clock << " now=" << now_clock << "\n";
            audio.destroyStreamingSource(source);
            return 1;
        }
        last_clock = std::max(last_clock, now_clock);
        std::this_thread::sleep_for(std::chrono::milliseconds(4));
    }

    audio.destroyStreamingSource(source);
    std::cout << "test_audio_stream_clock: all tests passed\n";
    return 0;
}
