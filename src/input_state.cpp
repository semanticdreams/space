#include "input_state.h"

#include <cstring>

InputState::InputState()
{
    keyboardState.currentValue = nullptr;
    std::memset(keyboardState.previousValue, 0, SDL_SCANCODE_COUNT);
}

void InputState::begin_frame()
{
    for (auto& [instance_id, gamepad] : gamepadStates) {
        (void)instance_id;
        if (gamepad) {
            gamepad->begin_frame();
        }
    }
}

void InputState::on_gamepad_connected(Sint32 deviceIndex, SDL_JoystickID instanceId, Uint64 timestamp)
{
    const std::shared_ptr<GamepadState> gamepad = ensure_gamepad(instanceId);
    gamepad->connect(deviceIndex, instanceId, timestamp);
    assign_primary_if_missing(instanceId);
}

void InputState::on_gamepad_disconnected(SDL_JoystickID instanceId, Uint64 timestamp)
{
    auto it = gamepadStates.find(instanceId);
    if (it != gamepadStates.end() && it->second) {
        it->second->disconnect(instanceId, timestamp);
        gamepadStates.erase(it);
    }
    if (primaryGamepadId == instanceId) {
        primaryGamepadId = 0;
        assign_primary_if_missing(0);
    }
}

void InputState::on_gamepad_button(Uint8 button, bool pressed, SDL_JoystickID instanceId, Uint64 timestamp)
{
    const std::shared_ptr<GamepadState> gamepad = ensure_gamepad(instanceId);
    gamepad->set_button(button, pressed, instanceId, timestamp);
    primaryGamepadId = instanceId;
}

void InputState::on_gamepad_axis(Uint8 axis, float value, SDL_JoystickID instanceId, Uint64 timestamp)
{
    const std::shared_ptr<GamepadState> gamepad = ensure_gamepad(instanceId);
    gamepad->set_axis(axis, value, instanceId, timestamp);
    primaryGamepadId = instanceId;
}

size_t InputState::gamepad_count() const
{
    return gamepadStates.size();
}

SDL_JoystickID InputState::primary_gamepad_id() const
{
    return primaryGamepadId;
}

const GamepadState* InputState::primary_gamepad() const
{
    return gamepad_by_id(primaryGamepadId);
}

GamepadState* InputState::primary_gamepad()
{
    return gamepad_by_id(primaryGamepadId);
}

const GamepadState* InputState::gamepad_by_id(SDL_JoystickID instanceId) const
{
    const auto it = gamepadStates.find(instanceId);
    if (it == gamepadStates.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

GamepadState* InputState::gamepad_by_id(SDL_JoystickID instanceId)
{
    auto it = gamepadStates.find(instanceId);
    if (it == gamepadStates.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

std::vector<SDL_JoystickID> InputState::gamepad_ids() const
{
    std::vector<SDL_JoystickID> ids;
    ids.reserve(gamepadStates.size());
    for (const auto& [instance_id, gamepad] : gamepadStates) {
        if (gamepad && gamepad->connected) {
            ids.push_back(instance_id);
        }
    }
    return ids;
}

std::shared_ptr<GamepadState> InputState::ensure_gamepad(SDL_JoystickID instanceId)
{
    auto it = gamepadStates.find(instanceId);
    if (it != gamepadStates.end() && it->second) {
        return it->second;
    }
    auto gamepad = std::make_shared<GamepadState>();
    gamepadStates[instanceId] = gamepad;
    return gamepad;
}

void InputState::assign_primary_if_missing(SDL_JoystickID preferredId)
{
    if (primaryGamepadId != 0 && gamepadStates.count(primaryGamepadId) > 0) {
        return;
    }
    if (preferredId != 0 && gamepadStates.count(preferredId) > 0) {
        primaryGamepadId = preferredId;
        return;
    }
    for (const auto& [instance_id, gamepad] : gamepadStates) {
        if (gamepad && gamepad->connected) {
            primaryGamepadId = instance_id;
            return;
        }
    }
    primaryGamepadId = 0;
}
