#include "input_mouse_state.h"

#include <algorithm>

void MouseState::begin_frame()
{
    std::copy(std::begin(currentButtons), std::end(currentButtons), std::begin(previousButtons));
    xrel = 0;
    yrel = 0;
    wheelX = 0;
    wheelY = 0;
}

void MouseState::update_from_mask(Uint32 mask)
{
    for (int button = 1; button < MAX_BUTTONS; ++button) {
        bool pressed = (mask & SDL_BUTTON(button)) != 0;
        currentButtons[index_for_button(static_cast<Uint8>(button))] = pressed ? 1 : 0;
    }
}

void MouseState::set_motion(int newX, int newY, int deltaX, int deltaY)
{
    x = newX;
    y = newY;
    xrel += deltaX;
    yrel += deltaY;
}

void MouseState::add_wheel(int deltaX, int deltaY)
{
    wheelX += deltaX;
    wheelY += deltaY;
}

void MouseState::set_button(Uint8 button, bool pressed)
{
    size_t idx = index_for_button(button);
    if (idx >= MAX_BUTTONS) {
        return;
    }
    currentButtons[idx] = pressed ? 1 : 0;
}

KeyStatus MouseState::getButtonState(Uint8 button) const
{
    size_t idx = index_for_button(button);
    if (idx >= MAX_BUTTONS) {
        return None;
    }

    if (previousButtons[idx] == 0) {
        if (currentButtons[idx] == 0) {
            return None;
        } else {
            return JustPressed;
        }
    } else {
        if (currentButtons[idx] == 0) {
            return JustReleased;
        } else {
            return Held;
        }
    }
}

bool MouseState::isUp(Uint8 button) const
{
    return !isDown(button);
}

bool MouseState::isFree(Uint8 button) const
{
    return getButtonState(button) == None;
}

bool MouseState::isJustPressed(Uint8 button) const
{
    return getButtonState(button) == JustPressed;
}

bool MouseState::isDown(Uint8 button) const
{
    size_t idx = index_for_button(button);
    if (idx >= MAX_BUTTONS) {
        return false;
    }
    return currentButtons[idx] == 1;
}

bool MouseState::isHeld(Uint8 button) const
{
    return getButtonState(button) == Held;
}

bool MouseState::isJustReleased(Uint8 button) const
{
    return getButtonState(button) == JustReleased;
}

size_t MouseState::index_for_button(Uint8 button) const
{
    if (button == 0) {
        return MAX_BUTTONS;
    }
    size_t idx = static_cast<size_t>(button);
    if (idx >= MAX_BUTTONS) {
        return MAX_BUTTONS;
    }
    return idx;
}
