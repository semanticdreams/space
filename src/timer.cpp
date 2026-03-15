#include "timer.h"

#include <algorithm>

Uint64 Timer::computeDeltaTime() {
    frameStart = SDL_GetTicks();
    Uint64 dt = frameStart - lastFrame;
    lastFrame = frameStart;
    return dt;
}

void Timer::delayTime() {
    if (targetFps <= 0) {
        // Minimized/off mode: avoid busy-looping while still processing events.
        SDL_Delay(100);
        return;
    }

    const Uint64 frameDelay = static_cast<Uint64>(1000 / targetFps);
    frameTime = SDL_GetTicks() - frameStart;
    if (frameTime < frameDelay) {
        SDL_Delay(frameDelay - frameTime);
    }
}

void Timer::reset()
{
    frameStart = SDL_GetTicks();
    lastFrame = frameStart;
    frameTime = 0;
}

void Timer::setTargetFps(int fps)
{
    targetFps = std::clamp(fps, kMinFps, kMaxFps);
}

int Timer::getTargetFps() const
{
    return targetFps;
}
