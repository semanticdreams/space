#include "input_keyboard_state.h"

bool KeyboardState::getKeyValue(SDL_Scancode keyCode) const
{
    if (keyCode < 0 || keyCode >= SDL_SCANCODE_COUNT || currentValue == nullptr) {
        return false;
    }
    return currentValue[keyCode];
}

KeyStatus KeyboardState::getKeyState(SDL_Scancode keyCode) const
{
    if (keyCode < 0 || keyCode >= SDL_SCANCODE_COUNT || currentValue == nullptr) {
        return None;
    }

    if (!previousValue[keyCode]) {
        if (!currentValue[keyCode]) {
            return None;
        } else {
            return JustPressed;
        }
    } else {
        if (!currentValue[keyCode]) {
            return JustReleased;
        } else {
            return Held;
        }
    }
}

bool KeyboardState::isUp(SDL_Scancode keyCode) const
{
    return !getKeyValue(keyCode);
}

bool KeyboardState::isFree(SDL_Scancode keyCode) const
{
    return getKeyState(keyCode) == None;
}

bool KeyboardState::isJustPressed(SDL_Scancode keyCode) const
{
    return getKeyState(keyCode) == JustPressed;
}

bool KeyboardState::isDown(SDL_Scancode keyCode) const
{
    return getKeyValue(keyCode);
}

bool KeyboardState::isHeld(SDL_Scancode keyCode) const
{
    return getKeyState(keyCode) == Held;
}

bool KeyboardState::isJustReleased(SDL_Scancode keyCode) const
{
    return getKeyState(keyCode) == JustReleased;
}
