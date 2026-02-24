#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>

class VideoAudioChunkCounters {
public:
    void add_dropped(std::uint64_t count) {
        if (count == 0) {
            return;
        }
        dropped_.fetch_add(count, std::memory_order_relaxed);
    }

    void add_flushed(std::uint64_t count) {
        if (count == 0) {
            return;
        }
        flushed_.fetch_add(count, std::memory_order_relaxed);
    }

    std::uint64_t dropped() const {
        return dropped_.load(std::memory_order_relaxed);
    }

    std::uint64_t flushed() const {
        return flushed_.load(std::memory_order_relaxed);
    }

private:
    std::atomic<std::uint64_t> dropped_ { 0 };
    std::atomic<std::uint64_t> flushed_ { 0 };
};

class VideoAvDriftTracker {
public:
    explicit VideoAvDriftTracker(double window_seconds)
        : window_seconds_(window_seconds)
    {
    }

    void record(double drift_seconds, double now_seconds) {
        double abs_drift = std::abs(drift_seconds);
        max_abs_drift_seconds_ = std::max(max_abs_drift_seconds_, abs_drift);
        if (window_started_seconds_ < 0.0) {
            window_started_seconds_ = now_seconds;
        }
        window_max_abs_drift_seconds_ = std::max(window_max_abs_drift_seconds_, abs_drift);

        if ((now_seconds - window_started_seconds_) >= window_seconds_) {
            sampled_recent_max_abs_drift_seconds_ = window_max_abs_drift_seconds_;
            window_started_seconds_ = now_seconds;
            window_max_abs_drift_seconds_ = abs_drift;
        }
    }

    double max_abs_drift_seconds() const {
        return max_abs_drift_seconds_;
    }

    double recent_max_abs_drift_seconds() const {
        return std::max(sampled_recent_max_abs_drift_seconds_, window_max_abs_drift_seconds_);
    }

    double window_seconds() const {
        return window_seconds_;
    }

private:
    double window_seconds_ { 0.0 };
    double max_abs_drift_seconds_ { 0.0 };
    double sampled_recent_max_abs_drift_seconds_ { 0.0 };
    double window_started_seconds_ { -1.0 };
    double window_max_abs_drift_seconds_ { 0.0 };
};
