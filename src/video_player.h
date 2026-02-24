#pragma once

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>
#include <unordered_set>

#include <AL/al.h>
#include <glm/vec3.hpp>

#include "texture.h"
#include "video_telemetry.h"

class Audio;
class VideoManager;

class VideoPlayer {
public:
    struct Options {
        bool loop { false };
        bool autoplay { true };
        bool muted { false };
        bool positional_audio { false };
        glm::vec3 audio_position { 0.0f, 0.0f, 0.0f };
        glm::vec3 audio_velocity { 0.0f, 0.0f, 0.0f };
        glm::vec3 audio_direction { 0.0f, 0.0f, 0.0f };
        float audio_gain { 1.0f };
        float audio_pitch { 1.0f };
        float audio_max_distance { 300.0f };
        float audio_rolloff_factor { 0.05f };
        float audio_reference_distance { 10.0f };
        float audio_min_gain { 0.0f };
        float audio_max_gain { 1.0f };
        float audio_cone_inner_angle { 360.0f };
        float audio_cone_outer_angle { 360.0f };
        float audio_cone_outer_gain { 0.0f };
    };

    VideoPlayer(VideoManager& manager, const std::string& path);
    VideoPlayer(VideoManager& manager, const std::string& path, Options options);
    ~VideoPlayer();

    VideoPlayer(const VideoPlayer&) = delete;
    VideoPlayer& operator=(const VideoPlayer&) = delete;

    void play();
    void pause();
    void stop();
    void seek(double seconds);
    void update(uint32_t dt_ms);
    void drop();

    bool ready() const;
    bool ended() const;
    bool playing() const;

    double duration() const;
    double position() const;
    std::string last_error() const;
    double last_clock_seconds() const;
    double last_av_drift_seconds() const;
    double max_av_drift_seconds() const;
    double recent_max_av_drift_seconds() const;
    double recent_av_drift_window_seconds() const;
    std::uint64_t dropped_video_frames() const;
    bool has_audio_clock() const;
    bool audio_available() const;
    bool audio_active() const;
    std::size_t queued_audio_chunks() const;
    std::uint64_t dropped_audio_chunks() const;
    std::uint64_t flushed_audio_chunks() const;
    std::uint64_t decode_loop_iterations() const;
    std::uint64_t decode_wait_milliseconds() const;
    void set_positional_audio(bool enabled);
    bool positional_audio() const;
    void set_audio_position(const glm::vec3& position);

    Texture2D& texture();

private:
    friend class VideoManager;
    struct Frame {
        std::vector<std::uint8_t> rgba;
        int width { 0 };
        int height { 0 };
        double pts_seconds { 0.0 };
    };
    struct AudioChunk {
        std::vector<std::int16_t> samples;
        int channels { 0 };
        int sample_rate { 0 };
        double pts_seconds { 0.0 };
    };

    void decode_loop();
    void initialize_gl_texture(int width, int height);
    void upload_frame(const Frame& frame);
    void clear_queued_frames();
    void clear_queued_audio_chunks(bool count_as_flush);
    void update_av_drift_metrics(double av_drift_seconds);
    void apply_audio_source_parameters(Audio& audio);

    std::string path_;
    bool loop_ { false };
    bool muted_ { false };

    mutable std::mutex state_mutex_;
    bool play_active_ { false };
    bool ready_ { false };
    bool ended_ { false };
    double base_position_seconds_ { 0.0 };
    std::chrono::steady_clock::time_point play_started_at_ {};

    std::mutex command_mutex_;
    std::optional<double> pending_seek_seconds_;
    std::condition_variable decode_wake_cv_;

    std::mutex queue_mutex_;
    std::deque<Frame> decoded_frames_;
    static constexpr std::size_t kMaxBufferedFrames = 8;
    mutable std::mutex audio_queue_mutex_;
    std::deque<AudioChunk> decoded_audio_chunks_;
    static constexpr std::size_t kMaxBufferedAudioChunks = 24;
    std::atomic<bool> has_audio_stream_ { false };

    std::atomic<bool> running_ { true };
    std::atomic<bool> decode_finished_ { false };
    std::atomic<double> duration_seconds_ { 0.0 };
    std::thread decode_thread_;
    std::atomic<bool> dropped_ { false };

    Texture2D texture_;
    bool texture_initialized_ { false };
    int texture_width_ { 0 };
    int texture_height_ { 0 };

    double displayed_pts_seconds_ { -1.0 };
    mutable std::mutex audio_source_mutex_;
    ALuint audio_source_ { 0 };
    bool source_positional_audio_ { false };
    mutable std::mutex error_mutex_;
    std::string last_error_;

    void set_last_error(const std::string& message);
    void clear_last_error();
    void on_audio_reset(Audio* previous_audio);

    void shutdown_player();

    VideoManager* manager_ { nullptr };
    std::atomic<double> last_clock_seconds_ { 0.0 };
    std::atomic<double> last_av_drift_seconds_ { 0.0 };
    std::atomic<double> max_av_drift_seconds_ { 0.0 };
    std::atomic<double> recent_max_av_drift_seconds_ { 0.0 };
    std::atomic<std::uint64_t> dropped_video_frames_ { 0 };
    VideoAudioChunkCounters audio_chunk_counters_ {};
    std::atomic<bool> has_audio_clock_ { false };
    static constexpr double kRecentAvDriftWindowSeconds = 2.0;
    mutable std::mutex drift_window_mutex_;
    VideoAvDriftTracker drift_tracker_ { kRecentAvDriftWindowSeconds };
    std::atomic<std::uint64_t> decode_loop_iterations_ { 0 };
    std::atomic<std::uint64_t> decode_wait_milliseconds_ { 0 };
    bool positional_audio_ { false };
    glm::vec3 audio_position_ { 0.0f, 0.0f, 0.0f };
    glm::vec3 audio_velocity_ { 0.0f, 0.0f, 0.0f };
    glm::vec3 audio_direction_ { 0.0f, 0.0f, 0.0f };
    float audio_gain_ { 1.0f };
    float audio_pitch_ { 1.0f };
    float audio_max_distance_ { 300.0f };
    float audio_rolloff_factor_ { 0.05f };
    float audio_reference_distance_ { 10.0f };
    float audio_min_gain_ { 0.0f };
    float audio_max_gain_ { 1.0f };
    float audio_cone_inner_angle_ { 360.0f };
    float audio_cone_outer_angle_ { 360.0f };
    float audio_cone_outer_gain_ { 0.0f };
};

class VideoManager {
public:
    void set_audio(Audio* audio);
    Audio* current_audio() const;
    bool has_audio() const;
    void register_player(VideoPlayer* player);
    void unregister_player(VideoPlayer* player);
    void update_all(uint32_t dt_ms);
    void drop_all();
    void on_audio_reset(Audio* previous_audio);

private:
    mutable std::mutex audio_mutex_;
    Audio* audio_ { nullptr };
    mutable std::mutex players_mutex_;
    std::unordered_set<VideoPlayer*> players_;
};
