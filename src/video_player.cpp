#include "video_player.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <sstream>
#include <stdexcept>
#include <thread>

#include <epoxy/gl.h>
#ifdef __linux__
#include <SDL2/SDL.h>
#elif _WIN32
#include <SDL.h>
#endif

#include "asset_manager.h"
#include "audio.h"

#if defined(SPACE_HAS_FFMPEG)
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/rational.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}
#endif

namespace {

std::string resolve_media_path(const std::string& path) {
    if (path.empty()) {
        return path;
    }
    namespace fs = std::filesystem;
    fs::path p(path);
    if (p.is_absolute() && fs::exists(p)) {
        return p.string();
    }
    if (fs::exists(p)) {
        return fs::absolute(p).string();
    }
    std::string asset_path = AssetManager::getAssetPath(path);
    if (!asset_path.empty() && fs::exists(asset_path)) {
        return asset_path;
    }
    return path;
}

double clamp_non_negative(double value) {
    return value < 0.0 ? 0.0 : value;
}

double wrap_position(double value, double duration, bool loop) {
    double clamped = clamp_non_negative(value);
    if (!loop || duration <= 0.0) {
        return clamped;
    }
    double wrapped = std::fmod(clamped, duration);
    if (wrapped < 0.0) {
        wrapped += duration;
    }
    return wrapped;
}

bool has_gl_context() {
#if defined(__linux__) || defined(_WIN32)
    return SDL_GL_GetCurrentContext() != nullptr;
#else
    return true;
#endif
}

#if defined(SPACE_HAS_FFMPEG)
std::string av_error_string(int errnum) {
    char buffer[AV_ERROR_MAX_STRING_SIZE] = {};
    av_strerror(errnum, buffer, sizeof(buffer));
    return std::string(buffer);
}
#endif

} // namespace

VideoPlayer::VideoPlayer(VideoManager& manager, const std::string& path)
    : VideoPlayer(manager, path, Options())
{
}

VideoPlayer::VideoPlayer(VideoManager& manager, const std::string& path, Options options)
    : path_(resolve_media_path(path))
    , loop_(options.loop)
    , muted_(options.muted)
{
#if !defined(SPACE_HAS_FFMPEG)
    (void) options;
    throw std::runtime_error("video module unavailable: built without FFmpeg support");
#else
    manager_ = &manager;
    manager_->register_player(this);
    clear_last_error();
    if (options.autoplay) {
        std::lock_guard<std::mutex> lock(state_mutex_);
        play_active_ = true;
        play_started_at_ = std::chrono::steady_clock::now();
        ended_ = false;
    }
    decode_thread_ = std::thread([this]() { decode_loop(); });
#endif
}

VideoPlayer::~VideoPlayer() {
    shutdown_player();
}

void VideoPlayer::play() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (play_active_) {
        return;
    }
    if (ended_) {
        base_position_seconds_ = 0.0;
        ended_ = false;
        std::lock_guard<std::mutex> cmd_lock(command_mutex_);
        pending_seek_seconds_ = 0.0;
    }
    play_started_at_ = std::chrono::steady_clock::now();
    play_active_ = true;
    Audio* audio = manager_ ? manager_->current_audio() : nullptr;
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (audio_source_ != 0 && audio) {
        audio->playSource(audio_source_);
    }
}

void VideoPlayer::pause() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (!play_active_) {
        return;
    }
    Audio* audio = manager_ ? manager_->current_audio() : nullptr;
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (audio_source_ != 0 && audio) {
        base_position_seconds_ = audio->getStreamingClockSeconds(audio_source_, base_position_seconds_);
        audio->pauseSource(audio_source_);
    } else {
        auto now = std::chrono::steady_clock::now();
        std::chrono::duration<double> elapsed = now - play_started_at_;
        base_position_seconds_ = clamp_non_negative(base_position_seconds_ + elapsed.count());
    }
    play_active_ = false;
}

void VideoPlayer::stop() {
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        play_active_ = false;
        base_position_seconds_ = 0.0;
        ended_ = false;
        displayed_pts_seconds_ = -1.0;
    }
    {
        std::lock_guard<std::mutex> cmd_lock(command_mutex_);
        pending_seek_seconds_ = 0.0;
    }
    decode_wake_cv_.notify_all();
    clear_queued_frames();
    clear_queued_audio_chunks(true);
    Audio* audio = manager_ ? manager_->current_audio() : nullptr;
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (audio_source_ != 0 && audio) {
        audio->destroyStreamingSource(audio_source_);
        audio_source_ = 0;
    }
}

void VideoPlayer::seek(double seconds) {
    double clamped = clamp_non_negative(seconds);
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        base_position_seconds_ = clamped;
        ended_ = false;
        displayed_pts_seconds_ = -1.0;
        if (play_active_) {
            play_started_at_ = std::chrono::steady_clock::now();
        }
    }
    {
        std::lock_guard<std::mutex> cmd_lock(command_mutex_);
        pending_seek_seconds_ = clamped;
    }
    decode_wake_cv_.notify_all();
    clear_queued_frames();
    clear_queued_audio_chunks(true);
    Audio* audio = manager_ ? manager_->current_audio() : nullptr;
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (audio_source_ != 0 && audio) {
        audio->destroyStreamingSource(audio_source_);
        audio_source_ = 0;
    }
}

void VideoPlayer::update(uint32_t dt_ms) {
    (void) dt_ms;
#if !defined(SPACE_HAS_FFMPEG)
    return;
#else
    if (dropped_.load()) {
        return;
    }
    double playback_position = 0.0;
    bool is_playing = false;
    double known_duration = duration_seconds_.load();
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        playback_position = base_position_seconds_;
        is_playing = play_active_;
        if (is_playing) {
            std::chrono::duration<double> elapsed = std::chrono::steady_clock::now() - play_started_at_;
            playback_position = clamp_non_negative(playback_position + elapsed.count());
        }
    }
    playback_position = wrap_position(playback_position, known_duration, loop_);

    Audio* audio = manager_ ? manager_->current_audio() : nullptr;
    if (has_audio_stream_.load() && audio) {
        std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
        if (audio_source_ == 0) {
            audio_source_ = audio->createStreamingSource(glm::vec3(0.0f), false);
        }
        if (audio_source_ != 0) {
            audio->reclaimProcessedStreamBuffers(audio_source_);
            if (is_playing) {
                bool dequeued_audio = false;
                {
                    std::lock_guard<std::mutex> lock(audio_queue_mutex_);
                    while (!decoded_audio_chunks_.empty()) {
                        const AudioChunk& front = decoded_audio_chunks_.front();
                        if (front.pts_seconds > playback_position + 0.250) {
                            break;
                        }
                        audio->queueStreamPcm16(audio_source_,
                                                front.samples.data(),
                                                front.samples.size(),
                                                front.channels,
                                                front.sample_rate,
                                                front.pts_seconds);
                        decoded_audio_chunks_.pop_front();
                        dequeued_audio = true;
                    }
                }
                if (dequeued_audio) {
                    decode_wake_cv_.notify_one();
                }
                double audio_clock_seconds = audio->getStreamingClockSeconds(audio_source_, playback_position);
                audio_clock_seconds = wrap_position(audio_clock_seconds, known_duration, loop_);
                last_clock_seconds_.store(audio_clock_seconds, std::memory_order_relaxed);
                has_audio_clock_.store(true, std::memory_order_relaxed);
                double av_drift_seconds = audio_clock_seconds - playback_position;
                last_av_drift_seconds_.store(av_drift_seconds, std::memory_order_relaxed);
                update_av_drift_metrics(av_drift_seconds);
                playback_position = audio_clock_seconds;
                std::lock_guard<std::mutex> state_lock(state_mutex_);
                base_position_seconds_ = playback_position;
                play_started_at_ = std::chrono::steady_clock::now();
            } else {
                audio->pauseSource(audio_source_);
            }
        }
    } else {
        has_audio_clock_.store(false, std::memory_order_relaxed);
    }

    Frame chosen;
    bool has_chosen = false;
    std::uint64_t dropped_this_update = 0;
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        while (!decoded_frames_.empty()) {
            const Frame& front = decoded_frames_.front();
            if (front.pts_seconds <= playback_position + 0.010) {
                if (has_chosen) {
                    dropped_this_update += 1;
                }
                chosen = std::move(decoded_frames_.front());
                decoded_frames_.pop_front();
                has_chosen = true;
            } else {
                break;
            }
        }
        if (!has_chosen && displayed_pts_seconds_ < 0.0 && !decoded_frames_.empty()) {
            chosen = std::move(decoded_frames_.front());
            decoded_frames_.pop_front();
            has_chosen = true;
        }
    }
    if (has_chosen) {
        decode_wake_cv_.notify_one();
    }
    if (dropped_this_update > 0) {
        dropped_video_frames_.fetch_add(dropped_this_update, std::memory_order_relaxed);
    }

    if (has_chosen) {
        upload_frame(chosen);
        displayed_pts_seconds_ = chosen.pts_seconds;
    }

    bool reached_end = decode_finished_.load() && !loop_;
    if (reached_end) {
        std::lock_guard<std::mutex> queue_lock(queue_mutex_);
        if (decoded_frames_.empty()) {
            std::lock_guard<std::mutex> state_lock(state_mutex_);
            if (play_active_) {
                play_active_ = false;
            }
            ended_ = true;
        }
    }
#endif
}

void VideoPlayer::drop() {
    shutdown_player();
}

bool VideoPlayer::ready() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return ready_;
}

bool VideoPlayer::ended() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return ended_;
}

bool VideoPlayer::playing() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return play_active_;
}

double VideoPlayer::duration() const {
    return duration_seconds_.load();
}

double VideoPlayer::position() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    double value = base_position_seconds_;
    if (play_active_) {
        std::chrono::duration<double> elapsed = std::chrono::steady_clock::now() - play_started_at_;
        value = clamp_non_negative(value + elapsed.count());
    }
    return wrap_position(value, duration_seconds_.load(), loop_);
}

std::string VideoPlayer::last_error() const {
    std::lock_guard<std::mutex> lock(error_mutex_);
    return last_error_;
}

double VideoPlayer::last_clock_seconds() const {
    return last_clock_seconds_.load(std::memory_order_relaxed);
}

double VideoPlayer::last_av_drift_seconds() const {
    return last_av_drift_seconds_.load(std::memory_order_relaxed);
}

double VideoPlayer::max_av_drift_seconds() const {
    return max_av_drift_seconds_.load(std::memory_order_relaxed);
}

double VideoPlayer::recent_max_av_drift_seconds() const {
    std::lock_guard<std::mutex> lock(drift_window_mutex_);
    return drift_tracker_.recent_max_abs_drift_seconds();
}

double VideoPlayer::recent_av_drift_window_seconds() const {
    return kRecentAvDriftWindowSeconds;
}

std::uint64_t VideoPlayer::dropped_video_frames() const {
    return dropped_video_frames_.load(std::memory_order_relaxed);
}

bool VideoPlayer::has_audio_clock() const {
    return has_audio_clock_.load(std::memory_order_relaxed);
}

bool VideoPlayer::audio_available() const {
    return has_audio_stream_.load(std::memory_order_relaxed);
}

bool VideoPlayer::audio_active() const {
    if (!has_audio_stream_.load(std::memory_order_relaxed) || !manager_) {
        return false;
    }
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (audio_source_ == 0) {
        return false;
    }
    return manager_->current_audio() != nullptr;
}

std::size_t VideoPlayer::queued_audio_chunks() const {
    std::lock_guard<std::mutex> lock(audio_queue_mutex_);
    return decoded_audio_chunks_.size();
}

std::uint64_t VideoPlayer::dropped_audio_chunks() const {
    return audio_chunk_counters_.dropped();
}

std::uint64_t VideoPlayer::flushed_audio_chunks() const {
    return audio_chunk_counters_.flushed();
}

std::uint64_t VideoPlayer::decode_loop_iterations() const {
    return decode_loop_iterations_.load(std::memory_order_relaxed);
}

std::uint64_t VideoPlayer::decode_wait_milliseconds() const {
    return decode_wait_milliseconds_.load(std::memory_order_relaxed);
}

void VideoPlayer::set_last_error(const std::string& message) {
    std::lock_guard<std::mutex> lock(error_mutex_);
    last_error_ = message;
}

void VideoPlayer::clear_last_error() {
    std::lock_guard<std::mutex> lock(error_mutex_);
    last_error_.clear();
}

Texture2D& VideoPlayer::texture() {
    return texture_;
}

void VideoPlayer::initialize_gl_texture(int width, int height) {
    if (!has_gl_context()) {
        texture_initialized_ = true;
        texture_width_ = width;
        texture_height_ = height;
        texture_.width = width;
        texture_.height = height;
        texture_.n = 4;
        texture_.internalFormat = GL_RGBA;
        texture_.imageFormat = GL_RGBA;
        return;
    }
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture_.id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, 0);

    texture_initialized_ = true;
    texture_width_ = width;
    texture_height_ = height;
    texture_.width = width;
    texture_.height = height;
    texture_.n = 4;
    texture_.internalFormat = GL_RGBA;
    texture_.imageFormat = GL_RGBA;
}

void VideoPlayer::upload_frame(const Frame& frame) {
    if (frame.width <= 0 || frame.height <= 0 || frame.rgba.empty()) {
        return;
    }
    if (!texture_initialized_ || texture_width_ != frame.width || texture_height_ != frame.height) {
        initialize_gl_texture(frame.width, frame.height);
    }

    if (has_gl_context()) {
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture_.id);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexSubImage2D(GL_TEXTURE_2D,
                        0,
                        0,
                        0,
                        frame.width,
                        frame.height,
                        GL_RGBA,
                        GL_UNSIGNED_BYTE,
                        frame.rgba.data());
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    std::lock_guard<std::mutex> lock(state_mutex_);
    ready_ = true;
    texture_.ready = true;
}

void VideoPlayer::clear_queued_frames() {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    decoded_frames_.clear();
    decode_wake_cv_.notify_one();
}

void VideoPlayer::clear_queued_audio_chunks(bool count_as_flush) {
    std::lock_guard<std::mutex> lock(audio_queue_mutex_);
    std::size_t cleared = decoded_audio_chunks_.size();
    decoded_audio_chunks_.clear();
    if (count_as_flush && cleared > 0) {
        audio_chunk_counters_.add_flushed(static_cast<std::uint64_t>(cleared));
    }
    decode_wake_cv_.notify_one();
}

void VideoPlayer::update_av_drift_metrics(double av_drift_seconds) {
    std::lock_guard<std::mutex> lock(drift_window_mutex_);
    double now_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
    drift_tracker_.record(av_drift_seconds, now_seconds);
    max_av_drift_seconds_.store(drift_tracker_.max_abs_drift_seconds(), std::memory_order_relaxed);
    recent_max_av_drift_seconds_.store(drift_tracker_.recent_max_abs_drift_seconds(), std::memory_order_relaxed);
}

void VideoPlayer::decode_loop() {
#if !defined(SPACE_HAS_FFMPEG)
    return;
#else
    AVFormatContext* format_ctx = nullptr;
    int open_result = avformat_open_input(&format_ctx, path_.c_str(), nullptr, nullptr);
    if (open_result < 0) {
        set_last_error("video: avformat_open_input failed: " + av_error_string(open_result));
        return;
    }

    int stream_info_result = avformat_find_stream_info(format_ctx, nullptr);
    if (stream_info_result < 0) {
        set_last_error("video: avformat_find_stream_info failed: " + av_error_string(stream_info_result));
        avformat_close_input(&format_ctx);
        return;
    }

    int video_stream_index = av_find_best_stream(format_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (video_stream_index < 0) {
        set_last_error("video: no decodable video stream found");
        avformat_close_input(&format_ctx);
        return;
    }
    int audio_stream_index = muted_ ? -1 : av_find_best_stream(format_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);

    AVStream* video_stream = format_ctx->streams[video_stream_index];
    const AVCodec* codec = avcodec_find_decoder(video_stream->codecpar->codec_id);
    if (!codec) {
        set_last_error("video: missing decoder for video codec");
        avformat_close_input(&format_ctx);
        return;
    }

    AVCodecContext* codec_ctx = avcodec_alloc_context3(codec);
    if (!codec_ctx) {
        set_last_error("video: failed to allocate video codec context");
        avformat_close_input(&format_ctx);
        return;
    }

    int codec_params_result = avcodec_parameters_to_context(codec_ctx, video_stream->codecpar);
    if (codec_params_result < 0) {
        set_last_error("video: avcodec_parameters_to_context failed: " + av_error_string(codec_params_result));
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&format_ctx);
        return;
    }

    int codec_open_result = avcodec_open2(codec_ctx, codec, nullptr);
    if (codec_open_result < 0) {
        set_last_error("video: avcodec_open2 failed: " + av_error_string(codec_open_result));
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&format_ctx);
        return;
    }

    AVStream* audio_stream = nullptr;
    AVCodecContext* audio_codec_ctx = nullptr;
    SwrContext* swr_ctx = nullptr;
    int out_channels = 0;
    int out_sample_rate = 0;
    if (audio_stream_index >= 0) {
        audio_stream = format_ctx->streams[audio_stream_index];
        const AVCodec* audio_codec = avcodec_find_decoder(audio_stream->codecpar->codec_id);
        if (audio_codec) {
            audio_codec_ctx = avcodec_alloc_context3(audio_codec);
            if (audio_codec_ctx &&
                avcodec_parameters_to_context(audio_codec_ctx, audio_stream->codecpar) >= 0 &&
                avcodec_open2(audio_codec_ctx, audio_codec, nullptr) >= 0) {
                out_sample_rate = std::max(1, audio_codec_ctx->sample_rate);
#if LIBAVUTIL_VERSION_MAJOR >= 57
                int input_channels = audio_codec_ctx->ch_layout.nb_channels;
                if (input_channels <= 0) {
                    input_channels = 1;
                }
                out_channels = input_channels > 1 ? 2 : 1;

                AVChannelLayout out_layout;
                av_channel_layout_default(&out_layout, out_channels);

                const AVChannelLayout* in_layout = &audio_codec_ctx->ch_layout;
                AVChannelLayout fallback_in_layout;
                bool fallback_in_layout_used = false;
                if (in_layout->nb_channels <= 0) {
                    av_channel_layout_default(&fallback_in_layout, input_channels);
                    in_layout = &fallback_in_layout;
                    fallback_in_layout_used = true;
                }

                SwrContext* candidate = nullptr;
                int swr_alloc_result = swr_alloc_set_opts2(&candidate,
                                                           &out_layout,
                                                           AV_SAMPLE_FMT_S16,
                                                           out_sample_rate,
                                                           in_layout,
                                                           audio_codec_ctx->sample_fmt,
                                                           audio_codec_ctx->sample_rate,
                                                           0,
                                                           nullptr);
                av_channel_layout_uninit(&out_layout);
                if (fallback_in_layout_used) {
                    av_channel_layout_uninit(&fallback_in_layout);
                }
                if (swr_alloc_result >= 0) {
                    swr_ctx = candidate;
                }
#else
                out_channels = audio_codec_ctx->channels > 1 ? 2 : 1;
                int64_t out_layout = out_channels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
                int64_t in_layout = audio_codec_ctx->channel_layout;
                if (in_layout == 0) {
                    in_layout = av_get_default_channel_layout(audio_codec_ctx->channels);
                }
                swr_ctx = swr_alloc_set_opts(nullptr,
                                             out_layout,
                                             AV_SAMPLE_FMT_S16,
                                             out_sample_rate,
                                             in_layout,
                                             audio_codec_ctx->sample_fmt,
                                             audio_codec_ctx->sample_rate,
                                             0,
                                             nullptr);
#endif
                if (!swr_ctx || swr_init(swr_ctx) < 0) {
                    if (swr_ctx) {
                        swr_free(&swr_ctx);
                    }
                    avcodec_free_context(&audio_codec_ctx);
                    audio_codec_ctx = nullptr;
                    audio_stream = nullptr;
                } else {
                    has_audio_stream_.store(true);
                }
            } else {
                if (audio_codec_ctx) {
                    avcodec_free_context(&audio_codec_ctx);
                }
                audio_codec_ctx = nullptr;
            }
        }
    }

    if (format_ctx->duration > 0) {
        duration_seconds_.store(static_cast<double>(format_ctx->duration) / static_cast<double>(AV_TIME_BASE));
    }

    SwsContext* sws_ctx = nullptr;

    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    if (!packet || !frame) {
        set_last_error("video: failed to allocate ffmpeg packet/frame");
        if (packet) {
            av_packet_free(&packet);
        }
        if (frame) {
            av_frame_free(&frame);
        }
        sws_freeContext(sws_ctx);
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&format_ctx);
        return;
    }

    clear_last_error();

    auto process_decoded_video_frames = [&](bool drain_only) {
        while (running_.load()) {
            int recv = avcodec_receive_frame(codec_ctx, frame);
            if (recv == AVERROR(EAGAIN) || recv == AVERROR_EOF) {
                break;
            }
            if (recv < 0) {
                break;
            }

            const int width = frame->width;
            const int height = frame->height;
            if (width <= 0 || height <= 0) {
                continue;
            }

            Frame out;
            out.width = width;
            out.height = height;
            out.rgba.resize(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4);

            std::uint8_t* dst_data[4] = { nullptr, nullptr, nullptr, nullptr };
            int dst_linesize[4] = { 0, 0, 0, 0 };
            dst_data[0] = out.rgba.data();
            dst_linesize[0] = width * 4;

            sws_ctx = sws_getCachedContext(sws_ctx,
                                           width,
                                           height,
                                           static_cast<AVPixelFormat>(frame->format),
                                           width,
                                           height,
                                           AV_PIX_FMT_RGBA,
                                           SWS_BILINEAR,
                                           nullptr,
                                           nullptr,
                                           nullptr);
            if (!sws_ctx) {
                set_last_error("video: sws_getCachedContext failed");
                continue;
            }

            int scaled_rows = sws_scale(sws_ctx,
                                        frame->data,
                                        frame->linesize,
                                        0,
                                        height,
                                        dst_data,
                                        dst_linesize);
            if (scaled_rows != height) {
                set_last_error("video: sws_scale failed to convert full frame");
                continue;
            }
            // Video frame alpha is not meaningful for in-world playback; force opaque so blending does not
            // attenuate RGB when codecs/converters provide undefined or zero alpha.
            for (std::size_t i = 3; i < out.rgba.size(); i += 4) {
                out.rgba[i] = 255;
            }

            int64_t pts = frame->best_effort_timestamp;
            if (pts == AV_NOPTS_VALUE) {
                if (video_stream->time_base.den > 0 && video_stream->time_base.num > 0) {
                    pts = frame->pkt_dts;
                }
            }
            if (pts != AV_NOPTS_VALUE) {
                out.pts_seconds = pts * av_q2d(video_stream->time_base);
            } else {
                out.pts_seconds = 0.0;
            }

            {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                decoded_frames_.push_back(std::move(out));
                while (decoded_frames_.size() > kMaxBufferedFrames) {
                    decoded_frames_.pop_front();
                    dropped_video_frames_.fetch_add(1, std::memory_order_relaxed);
                }
            }

            if (!drain_only) {
                std::lock_guard<std::mutex> state_lock(state_mutex_);
                ended_ = false;
            }
        }
    };

    double fallback_audio_pts_seconds = 0.0;
    auto process_decoded_audio_frames = [&](bool drain_only) {
        (void) drain_only;
        if (!audio_codec_ctx || !audio_stream || !swr_ctx) {
            return;
        }
        while (running_.load()) {
            int recv = avcodec_receive_frame(audio_codec_ctx, frame);
            if (recv == AVERROR(EAGAIN) || recv == AVERROR_EOF) {
                break;
            }
            if (recv < 0) {
                break;
            }
            if (frame->nb_samples <= 0) {
                continue;
            }

            int max_out_samples = swr_get_out_samples(swr_ctx, frame->nb_samples);
            if (max_out_samples <= 0) {
                continue;
            }

            AudioChunk chunk;
            chunk.channels = out_channels;
            chunk.sample_rate = out_sample_rate;
            chunk.samples.resize(static_cast<std::size_t>(max_out_samples) * static_cast<std::size_t>(out_channels));
            std::uint8_t* out_data[1] = { reinterpret_cast<std::uint8_t*>(chunk.samples.data()) };
            int converted = swr_convert(swr_ctx,
                                        out_data,
                                        max_out_samples,
                                        const_cast<const std::uint8_t**>(frame->extended_data),
                                        frame->nb_samples);
            if (converted <= 0) {
                continue;
            }
            chunk.samples.resize(static_cast<std::size_t>(converted) * static_cast<std::size_t>(out_channels));

            int64_t pts = frame->best_effort_timestamp;
            if (pts == AV_NOPTS_VALUE) {
                pts = frame->pts;
            }
            if (pts != AV_NOPTS_VALUE) {
                chunk.pts_seconds = pts * av_q2d(audio_stream->time_base);
                fallback_audio_pts_seconds = chunk.pts_seconds;
            } else {
                chunk.pts_seconds = fallback_audio_pts_seconds;
            }
            fallback_audio_pts_seconds = chunk.pts_seconds +
                                         static_cast<double>(converted) /
                                             static_cast<double>(std::max(1, out_sample_rate));

            std::lock_guard<std::mutex> lock(audio_queue_mutex_);
            decoded_audio_chunks_.push_back(std::move(chunk));
            while (decoded_audio_chunks_.size() > kMaxBufferedAudioChunks) {
                decoded_audio_chunks_.pop_front();
                audio_chunk_counters_.add_dropped(1);
            }
        }
    };

    auto buffers_full = [&]() {
        {
            std::lock_guard<std::mutex> lock(queue_mutex_);
            if (decoded_frames_.size() >= kMaxBufferedFrames) {
                return true;
            }
        }
        if (audio_codec_ctx) {
            std::lock_guard<std::mutex> lock(audio_queue_mutex_);
            if (decoded_audio_chunks_.size() >= kMaxBufferedAudioChunks) {
                return true;
            }
        }
        return false;
    };

    while (running_.load()) {
        decode_loop_iterations_.fetch_add(1, std::memory_order_relaxed);
        {
            std::optional<double> seek_request;
            {
                std::lock_guard<std::mutex> cmd_lock(command_mutex_);
                if (pending_seek_seconds_.has_value()) {
                    seek_request = pending_seek_seconds_;
                    pending_seek_seconds_.reset();
                }
            }
            if (seek_request.has_value()) {
                int64_t ts = static_cast<int64_t>(seek_request.value() / av_q2d(video_stream->time_base));
                int seek_result = av_seek_frame(format_ctx, video_stream_index, ts, AVSEEK_FLAG_BACKWARD);
                if (seek_result < 0) {
                    set_last_error("video: av_seek_frame failed: " + av_error_string(seek_result));
                }
                avcodec_flush_buffers(codec_ctx);
                if (audio_codec_ctx) {
                    avcodec_flush_buffers(audio_codec_ctx);
                }
                decode_finished_.store(false);
            }
        }

        if (buffers_full()) {
            std::unique_lock<std::mutex> wait_lock(command_mutex_);
            auto wait_started_at = std::chrono::steady_clock::now();
            decode_wake_cv_.wait_for(wait_lock,
                                     std::chrono::milliseconds(5),
                                     [&]() {
                                         return !running_.load() ||
                                                pending_seek_seconds_.has_value() ||
                                                !buffers_full();
                                     });
            auto wait_elapsed =
                std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - wait_started_at);
            if (wait_elapsed.count() > 0) {
                decode_wait_milliseconds_.fetch_add(static_cast<std::uint64_t>(wait_elapsed.count()),
                                                    std::memory_order_relaxed);
            }
            continue;
        }

        int read_res = av_read_frame(format_ctx, packet);
        if (read_res < 0) {
            avcodec_send_packet(codec_ctx, nullptr);
            process_decoded_video_frames(true);
            if (audio_codec_ctx) {
                avcodec_send_packet(audio_codec_ctx, nullptr);
                process_decoded_audio_frames(true);
            }

            if (loop_) {
                int rewind_result = av_seek_frame(format_ctx, -1, 0, AVSEEK_FLAG_BACKWARD);
                if (rewind_result < 0) {
                    set_last_error("video: loop rewind failed: " + av_error_string(rewind_result));
                    decode_finished_.store(true);
                    break;
                }
                avcodec_flush_buffers(codec_ctx);
                if (audio_codec_ctx) {
                    avcodec_flush_buffers(audio_codec_ctx);
                }
                decode_finished_.store(false);
                continue;
            }

            decode_finished_.store(true);
            break;
        }

        if (packet->stream_index == video_stream_index) {
            int send_res = avcodec_send_packet(codec_ctx, packet);
            if (send_res >= 0) {
                process_decoded_video_frames(false);
            }
        } else if (audio_codec_ctx && packet->stream_index == audio_stream_index) {
            int send_res = avcodec_send_packet(audio_codec_ctx, packet);
            if (send_res >= 0) {
                process_decoded_audio_frames(false);
            }
        }
        av_packet_unref(packet);
    }

    av_frame_free(&frame);
    av_packet_free(&packet);
    if (sws_ctx) {
        sws_freeContext(sws_ctx);
    }
    if (swr_ctx) {
        swr_free(&swr_ctx);
    }
    if (audio_codec_ctx) {
        avcodec_free_context(&audio_codec_ctx);
    }
    avcodec_free_context(&codec_ctx);
    avformat_close_input(&format_ctx);
#endif
}

void VideoPlayer::shutdown_player() {
#if defined(SPACE_HAS_FFMPEG)
    if (dropped_.exchange(true)) {
        return;
    }
    running_.store(false);
    decode_wake_cv_.notify_all();
    if (decode_thread_.joinable()) {
        decode_thread_.join();
    }
    Audio* audio = manager_ ? manager_->current_audio() : nullptr;
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (audio_source_ != 0 && audio) {
        audio->destroyStreamingSource(audio_source_);
        audio_source_ = 0;
    }
    if (manager_) {
        manager_->unregister_player(this);
        manager_ = nullptr;
    }
#endif
}

void VideoPlayer::on_audio_reset(Audio* previous_audio) {
    std::lock_guard<std::mutex> source_lock(audio_source_mutex_);
    if (!previous_audio || audio_source_ == 0) {
        audio_source_ = 0;
        has_audio_clock_.store(false, std::memory_order_relaxed);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        base_position_seconds_ = previous_audio->getStreamingClockSeconds(audio_source_, base_position_seconds_);
        if (play_active_) {
            play_started_at_ = std::chrono::steady_clock::now();
        }
    }
    previous_audio->destroyStreamingSource(audio_source_);
    audio_source_ = 0;
    has_audio_clock_.store(false, std::memory_order_relaxed);
}

void VideoManager::set_audio(Audio* audio) {
    std::lock_guard<std::mutex> lock(audio_mutex_);
    audio_ = audio;
}

Audio* VideoManager::current_audio() const {
    std::lock_guard<std::mutex> lock(audio_mutex_);
    return audio_;
}

bool VideoManager::has_audio() const {
    return current_audio() != nullptr;
}

void VideoManager::register_player(VideoPlayer* player) {
    std::lock_guard<std::mutex> lock(players_mutex_);
    players_.insert(player);
}

void VideoManager::unregister_player(VideoPlayer* player) {
    std::lock_guard<std::mutex> lock(players_mutex_);
    players_.erase(player);
}

void VideoManager::drop_all() {
    std::vector<VideoPlayer*> snapshot;
    {
        std::lock_guard<std::mutex> lock(players_mutex_);
        snapshot.reserve(players_.size());
        for (VideoPlayer* player : players_) {
            snapshot.push_back(player);
        }
    }

    for (VideoPlayer* player : snapshot) {
        if (player) {
            player->drop();
        }
    }
}

void VideoManager::update_all(uint32_t dt_ms) {
    std::vector<VideoPlayer*> snapshot;
    {
        std::lock_guard<std::mutex> lock(players_mutex_);
        snapshot.reserve(players_.size());
        for (VideoPlayer* player : players_) {
            snapshot.push_back(player);
        }
    }

    for (VideoPlayer* player : snapshot) {
        if (player) {
            player->update(dt_ms);
        }
    }
}

void VideoManager::on_audio_reset(Audio* previous_audio) {
    std::vector<VideoPlayer*> snapshot;
    {
        std::lock_guard<std::mutex> lock(players_mutex_);
        snapshot.reserve(players_.size());
        for (VideoPlayer* player : players_) {
            snapshot.push_back(player);
        }
    }

    for (VideoPlayer* player : snapshot) {
        if (player) {
            player->on_audio_reset(previous_audio);
        }
    }
}
