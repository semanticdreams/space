#include "timer.h"

Uint64 Timer::computeDeltaTime() {
    frameStart = SDL_GetTicks();
    Uint64 dt = frameStart - lastFrame;
    lastFrame = frameStart;
    return dt;
}

void Timer::delayTime() {
    frameTime = SDL_GetTicks() - frameStart;
    if (frameTime < frameDelay) {
        SDL_Delay(frameDelay - frameTime);
    }
}
