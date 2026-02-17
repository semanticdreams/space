#include "input_state.h"

#include <cstring>

InputState::InputState()
{
    keyboardState.currentValue = nullptr;
    std::memset(keyboardState.previousValue, 0, SDL_NUM_SCANCODES);
}

void InputState::begin_frame()
{
    for (auto& [instance_id, controller] : controllerStates) {
        (void)instance_id;
        if (controller) {
            controller->begin_frame();
        }
    }
}

void InputState::on_controller_connected(Sint32 deviceIndex, SDL_JoystickID instanceId, Uint32 timestamp)
{
    const std::shared_ptr<GameControllerState> controller = ensure_controller(instanceId);
    controller->connect(deviceIndex, instanceId, timestamp);
    assign_primary_if_missing(instanceId);
}

void InputState::on_controller_disconnected(SDL_JoystickID instanceId, Uint32 timestamp)
{
    auto it = controllerStates.find(instanceId);
    if (it != controllerStates.end() && it->second) {
        it->second->disconnect(instanceId, timestamp);
        controllerStates.erase(it);
    }
    if (primaryControllerId == instanceId) {
        primaryControllerId = -1;
        assign_primary_if_missing(-1);
    }
}

void InputState::on_controller_button(Uint8 button, bool pressed, SDL_JoystickID instanceId, Uint32 timestamp)
{
    const std::shared_ptr<GameControllerState> controller = ensure_controller(instanceId);
    controller->set_button(button, pressed, instanceId, timestamp);
    primaryControllerId = instanceId;
}

void InputState::on_controller_axis(Uint8 axis, float value, SDL_JoystickID instanceId, Uint32 timestamp)
{
    const std::shared_ptr<GameControllerState> controller = ensure_controller(instanceId);
    controller->set_axis(axis, value, instanceId, timestamp);
    primaryControllerId = instanceId;
}

size_t InputState::controller_count() const
{
    return controllerStates.size();
}

SDL_JoystickID InputState::primary_controller_id() const
{
    return primaryControllerId;
}

const GameControllerState* InputState::primary_controller() const
{
    return controller_by_id(primaryControllerId);
}

GameControllerState* InputState::primary_controller()
{
    return controller_by_id(primaryControllerId);
}

const GameControllerState* InputState::controller_by_id(SDL_JoystickID instanceId) const
{
    const auto it = controllerStates.find(instanceId);
    if (it == controllerStates.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

GameControllerState* InputState::controller_by_id(SDL_JoystickID instanceId)
{
    auto it = controllerStates.find(instanceId);
    if (it == controllerStates.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

std::vector<SDL_JoystickID> InputState::controller_ids() const
{
    std::vector<SDL_JoystickID> ids;
    ids.reserve(controllerStates.size());
    for (const auto& [instance_id, controller] : controllerStates) {
        if (controller && controller->connected) {
            ids.push_back(instance_id);
        }
    }
    return ids;
}

std::shared_ptr<GameControllerState> InputState::ensure_controller(SDL_JoystickID instanceId)
{
    auto it = controllerStates.find(instanceId);
    if (it != controllerStates.end() && it->second) {
        return it->second;
    }
    auto controller = std::make_shared<GameControllerState>();
    controllerStates[instanceId] = controller;
    return controller;
}

void InputState::assign_primary_if_missing(SDL_JoystickID preferredId)
{
    if (primaryControllerId != -1 && controllerStates.count(primaryControllerId) > 0) {
        return;
    }
    if (preferredId != -1 && controllerStates.count(preferredId) > 0) {
        primaryControllerId = preferredId;
        return;
    }
    for (const auto& [instance_id, controller] : controllerStates) {
        if (controller && controller->connected) {
            primaryControllerId = instance_id;
            return;
        }
    }
    primaryControllerId = -1;
}
