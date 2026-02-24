#include "video_telemetry.h"

#include <cmath>
#include <cstdint>
#include <iostream>

namespace {

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

bool nearly_equal(double a, double b, double epsilon = 1e-9)
{
    return std::abs(a - b) <= epsilon;
}

} // namespace

int main()
{
    VideoAvDriftTracker drift_tracker(2.0);

    drift_tracker.record(0.10, 0.0);
    if (!check(nearly_equal(drift_tracker.max_abs_drift_seconds(), 0.10), "max drift should start at first sample")) {
        return 1;
    }
    if (!check(nearly_equal(drift_tracker.recent_max_abs_drift_seconds(), 0.10), "recent drift should include active window")) {
        return 1;
    }

    drift_tracker.record(-0.20, 0.5);
    if (!check(nearly_equal(drift_tracker.max_abs_drift_seconds(), 0.20), "max drift should track absolute value")) {
        return 1;
    }
    if (!check(nearly_equal(drift_tracker.recent_max_abs_drift_seconds(), 0.20), "recent drift should update within window")) {
        return 1;
    }

    drift_tracker.record(0.05, 2.1);
    if (!check(nearly_equal(drift_tracker.max_abs_drift_seconds(), 0.20), "max drift should remain after window rollover")) {
        return 1;
    }
    if (!check(nearly_equal(drift_tracker.recent_max_abs_drift_seconds(), 0.20), "recent drift should retain previous full window max")) {
        return 1;
    }

    drift_tracker.record(0.30, 2.2);
    if (!check(nearly_equal(drift_tracker.max_abs_drift_seconds(), 0.30), "max drift should update after rollover")) {
        return 1;
    }
    if (!check(nearly_equal(drift_tracker.recent_max_abs_drift_seconds(), 0.30), "recent drift should reflect current window max")) {
        return 1;
    }
    if (!check(nearly_equal(drift_tracker.window_seconds(), 2.0), "window size should roundtrip")) {
        return 1;
    }

    VideoAudioChunkCounters counters;
    counters.add_dropped(3);
    counters.add_flushed(2);
    counters.add_dropped(0);
    counters.add_flushed(0);
    counters.add_dropped(7);

    if (!check(counters.dropped() == static_cast<std::uint64_t>(10), "dropped counter should accumulate")) {
        return 1;
    }
    if (!check(counters.flushed() == static_cast<std::uint64_t>(2), "flushed counter should accumulate")) {
        return 1;
    }

    std::cout << "test_video_telemetry: all tests passed\n";
    return 0;
}
