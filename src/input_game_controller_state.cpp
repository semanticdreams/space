#include "input_game_controller_state.h"

#include <algorithm>
#include <cstring>
#include <stdexcept>

void GameControllerState::begin_frame()
{
    std::memcpy(previousButtons, currentButtons, sizeof(currentButtons));
}

void GameControllerState::connect(Sint32 newDeviceIndex, SDL_JoystickID newInstanceId, Uint32 timestamp)
{
    connected = true;
    deviceIndex = newDeviceIndex;
    instanceId = newInstanceId;
    updateTimestamp = timestamp;
}

void GameControllerState::disconnect(SDL_JoystickID removedInstanceId, Uint32 timestamp)
{
    if (!connected || (instanceId != -1 && instanceId != removedInstanceId)) {
        return;
    }
    connected = false;
    deviceIndex = -1;
    instanceId = -1;
    updateTimestamp = timestamp;
    std::memset(currentButtons, 0, sizeof(currentButtons));
    std::memset(previousButtons, 0, sizeof(previousButtons));
    std::fill(std::begin(axes), std::end(axes), 0.0F);
}

void GameControllerState::set_button(Uint8 button, bool pressed, SDL_JoystickID sourceInstanceId, Uint32 timestamp)
{
    const size_t index = index_for_button(button);
    connected = true;
    instanceId = sourceInstanceId;
    updateTimestamp = timestamp;
    currentButtons[index] = pressed ? 1 : 0;
}

void GameControllerState::set_axis(Uint8 axis, float value, SDL_JoystickID sourceInstanceId, Uint32 timestamp)
{
    const size_t index = index_for_axis(axis);
    connected = true;
    instanceId = sourceInstanceId;
    updateTimestamp = timestamp;
    axes[index] = std::clamp(value, -1.0F, 1.0F);
}

KeyStatus GameControllerState::getButtonState(Uint8 button) const
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

bool GameControllerState::isUp(Uint8 button) const
{
    const KeyStatus status = getButtonState(button);
    return status == KeyStatus::None || status == KeyStatus::JustReleased;
}

bool GameControllerState::isFree(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::None;
}

bool GameControllerState::isJustPressed(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::JustPressed;
}

bool GameControllerState::isDown(Uint8 button) const
{
    const KeyStatus status = getButtonState(button);
    return status == KeyStatus::JustPressed || status == KeyStatus::Held;
}

bool GameControllerState::isHeld(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::Held;
}

bool GameControllerState::isJustReleased(Uint8 button) const
{
    return getButtonState(button) == KeyStatus::JustReleased;
}

float GameControllerState::axis(Uint8 axisIndex) const
{
    return axes[index_for_axis(axisIndex)];
}

size_t GameControllerState::index_for_button(Uint8 button) const
{
    if (button >= MAX_BUTTONS) {
        throw std::out_of_range("controller button out of range");
    }
    return static_cast<size_t>(button);
}

size_t GameControllerState::index_for_axis(Uint8 axisIndex) const
{
    if (axisIndex >= MAX_AXES) {
        throw std::out_of_range("controller axis out of range");
    }
    return static_cast<size_t>(axisIndex);
}
