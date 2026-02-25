#include "input_gamepad_state.h"

#include <algorithm>
#include <cstring>
#include <stdexcept>

void GamepadState::begin_frame()
{
    std::memcpy(previousButtons, currentButtons, sizeof(currentButtons));
}

void GamepadState::connect(Sint32 newDeviceIndex, SDL_JoystickID newInstanceId, Uint64 timestamp)
{
    connected = true;
    deviceIndex = newDeviceIndex;
    instanceId = newInstanceId;
    updateTimestamp = timestamp;
}

void GamepadState::disconnect(SDL_JoystickID removedInstanceId, Uint64 timestamp)
{
    if (!connected || (instanceId != 0 && instanceId != removedInstanceId)) {
        return;
    }
    connected = false;
    deviceIndex = -1;
    instanceId = 0;
    updateTimestamp = timestamp;
    std::memset(currentButtons, 0, sizeof(currentButtons));
    std::memset(previousButtons, 0, sizeof(previousButtons));
    std::fill(std::begin(axes), std::end(axes), 0.0F);
}

void GamepadState::set_button(Uint8 button, bool pressed, SDL_JoystickID sourceInstanceId, Uint64 timestamp)
{
    const size_t index = index_for_button(button);
    connected = true;
    instanceId = sourceInstanceId;
    updateTimestamp = timestamp;
    currentButtons[index] = pressed ? 1 : 0;
}

void GamepadState::set_axis(Uint8 axis, float value, SDL_JoystickID sourceInstanceId, Uint64 timestamp)
{
    const size_t index = index_for_axis(axis);
    connected = true;
    instanceId = sourceInstanceId;
    updateTimestamp = timestamp;
    axes[index] = std::clamp(value, -1.0F, 1.0F);
}

KeyStatus GamepadState::getButtonState(Uint8 button) const
{
    const size_t index = index_for_button(button);
    const bool current = currentButtons[index] != 0;
    const bool previous = previousButtons[index] != 0;
    if (current && !previous) {
        return KeyStatus::JustPressed;
    }
    if (current && previous) {
        return KeyStatus::Held;
    }
    if (!current && previous) {
        return KeyStatus::JustReleased;
    }
    return KeyStatus::None;
}

bool GamepadState::isUp(Uint8 button) const
{
    const KeyStatus status = getButtonState(button);
    return status == KeyStatus::None || status == KeyStatus::JustReleased;
}

bool GamepadState::isFree(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::None;
}

bool GamepadState::isJustPressed(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::JustPressed;
}

bool GamepadState::isDown(Uint8 button) const
{
    const KeyStatus status = getButtonState(button);
    return status == KeyStatus::JustPressed || status == KeyStatus::Held;
}

bool GamepadState::isHeld(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::Held;
}

bool GamepadState::isJustReleased(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::JustReleased;
}

float GamepadState::axis(Uint8 axisIndex) const
{
    return axes[index_for_axis(axisIndex)];
}

size_t GamepadState::index_for_button(Uint8 button) const
{
    if (button >= MAX_BUTTONS) {
        throw std::out_of_range("gamepad button out of range");
    }
    return static_cast<size_t>(button);
}

size_t GamepadState::index_for_axis(Uint8 axisIndex) const
{
    if (axisIndex >= MAX_AXES) {
        throw std::out_of_range("gamepad axis out of range");
    }
    return static_cast<size_t>(axisIndex);
}
