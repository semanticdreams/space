#ifndef INPUT_KEYBOARD_STATE_H
#define INPUT_KEYBOARD_STATE_H

#include <SDL3/SDL.h>

enum KeyStatus {
    None,
    JustPressed,
    Held,
    JustReleased
};

// Holds the keyboard state
class KeyboardState {
    friend class Engine;
    friend struct InputState;

public:
    // True when key is up or just released
    [[nodiscard]] bool isUp(SDL_Scancode) const;

    // True when key is up and not just released
    [[nodiscard]] bool isFree(SDL_Scancode) const;

    // True when key is just pressed
    [[nodiscard]] bool isJustPressed(SDL_Scancode) const;

    // True when key is down or just pressed
    [[nodiscard]] bool isDown(SDL_Scancode) const;

    // True when key is down and not just pressed
    [[nodiscard]] bool isHeld(SDL_Scancode) const;

    // True when key is just released
    [[nodiscard]] bool isJustReleased(SDL_Scancode) const;

    [[nodiscard]] KeyStatus getKeyState(SDL_Scancode) const;

private:
    const bool* currentValue;
    bool previousValue[SDL_SCANCODE_COUNT];

    // Get the boolean value of key
    [[nodiscard]] bool getKeyValue(SDL_Scancode) const;
};

#endif
