#ifndef TIMER_H
#define TIMER_H

#include <SDL3/SDL.h>

// Hold time related functions.
// In charge of computing the delta time and
// ensure smooth game ticking.
class Timer {
public:
    // Compute delta time as the number of milliseconds since last frame
    Uint64 computeDeltaTime();

    // Wait if the game run faster than the decided FPS
    void delayTime();

    void reset();
    void setTargetFps(int fps);
    [[nodiscard]] int getTargetFps() const;

private:
    static constexpr int kDefaultFps = 60;
    static constexpr int kMinFps = 0;
    static constexpr int kMaxFps = 240;

    // Time in milliseconds when frame starts
    Uint64 frameStart { 0 };

    // Last frame start time in milliseconds
    Uint64 lastFrame { 0 };

    // Time it tooks to run the loop. Used to cap framerate.
    Uint64 frameTime { 0 };
    int targetFps { kDefaultFps };
};

#endif
