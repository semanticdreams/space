#include "input_dial_type.h"

#include <SDL3/SDL.h>

#include <unordered_set>

InputDialType::InputDialType(InputState& inputStateRef)
    : inputState(&inputStateRef)
{
}

void InputDialType::reset()
{
    for (auto& [instance_id, dial] : dialByGamepad) {
        (void)instance_id;
        dial.reset();
    }
}

bool InputDialType::update()
{
    if (!inputState) {
        return false;
    }

    bool produced = false;
    const std::vector<SDL_JoystickID> ids = inputState->gamepad_ids();
    std::unordered_set<SDL_JoystickID> connected(ids.begin(), ids.end());

    for (auto it = dialByGamepad.begin(); it != dialByGamepad.end();) {
        if (connected.count(it->first) == 0) {
            activeGamepads.erase(it->first);
            remove_gamepad_subscriptions(it->first);
            it = dialByGamepad.erase(it);
        } else {
            ++it;
        }
    }

    for (const SDL_JoystickID instance_id : ids) {
        const GamepadState* gamepad = inputState->gamepad_by_id(instance_id);
        if (!gamepad) {
            continue;
        }
        DialType& dial = dialByGamepad[instance_id];
        if (dial.update(gamepad->axis(SDL_GAMEPAD_AXIS_LEFTX),
                        gamepad->axis(SDL_GAMEPAD_AXIS_LEFTY),
                        gamepad->axis(SDL_GAMEPAD_AXIS_RIGHTX),
                        gamepad->axis(SDL_GAMEPAD_AXIS_RIGHTY))) {
            produced = true;
        }
    }

    return produced;
}

bool InputDialType::update_primary()
{
    if (!inputState) {
        return false;
    }
    return update_gamepad(inputState->primary_gamepad_id());
}

bool InputDialType::update_gamepad(SDL_JoystickID instanceId)
{
    if (!inputState || instanceId == 0) {
        return false;
    }
    const GamepadState* gamepad = inputState->gamepad_by_id(instanceId);
    if (!gamepad) {
        deactivate_gamepad(instanceId);
        return false;
    }
    DialType& dial = dialByGamepad[instanceId];
    return dial.update(gamepad->axis(SDL_GAMEPAD_AXIS_LEFTX),
                       gamepad->axis(SDL_GAMEPAD_AXIS_LEFTY),
                       gamepad->axis(SDL_GAMEPAD_AXIS_RIGHTX),
                       gamepad->axis(SDL_GAMEPAD_AXIS_RIGHTY));
}

void InputDialType::activate_gamepad(SDL_JoystickID instanceId)
{
    if (instanceId != 0) {
        activeGamepads.insert(instanceId);
    }
}

void InputDialType::deactivate_gamepad(SDL_JoystickID instanceId)
{
    activeGamepads.erase(instanceId);
    dialByGamepad.erase(instanceId);
    remove_gamepad_subscriptions(instanceId);
}

bool InputDialType::is_gamepad_active(SDL_JoystickID instanceId) const
{
    return activeGamepads.count(instanceId) > 0;
}

bool InputDialType::process_gamepad(SDL_JoystickID instanceId)
{
    if (!is_gamepad_active(instanceId)) {
        return false;
    }
    if (!update_gamepad(instanceId)) {
        deactivate_gamepad(instanceId);
        return false;
    }
    const std::optional<DialTypePendingInput> pending = poll_gamepad(instanceId);
    if (!pending.has_value()) {
        return false;
    }
    dispatch(instanceId, pending.value());
    return true;
}

InputDialType::CallbackId InputDialType::register_callback(SDL_JoystickID instanceId, CallbackFn callback)
{
    if (!callback) {
        return 0;
    }
    const CallbackId id = nextCallbackId++;
    subscriptions[id] = Subscription {instanceId, std::move(callback)};
    subscriptionIdsByGamepad[instanceId].insert(id);
    return id;
}

bool InputDialType::unregister_callback(CallbackId callbackId)
{
    auto it = subscriptions.find(callbackId);
    if (it == subscriptions.end()) {
        return false;
    }
    const SDL_JoystickID instanceId = it->second.instanceId;
    subscriptions.erase(it);
    auto ids_it = subscriptionIdsByGamepad.find(instanceId);
    if (ids_it != subscriptionIdsByGamepad.end()) {
        ids_it->second.erase(callbackId);
        if (ids_it->second.empty()) {
            subscriptionIdsByGamepad.erase(ids_it);
        }
    }
    return true;
}

bool InputDialType::has_input() const
{
    if (!inputState) {
        return false;
    }
    const SDL_JoystickID primary_id = inputState->primary_gamepad_id();
    auto it = dialByGamepad.find(primary_id);
    return it != dialByGamepad.end() && it->second.has_input();
}

bool InputDialType::has_input_for(SDL_JoystickID instanceId) const
{
    auto it = dialByGamepad.find(instanceId);
    return it != dialByGamepad.end() && it->second.has_input();
}

std::optional<DialTypePendingInput> InputDialType::poll_primary()
{
    if (!inputState) {
        return std::nullopt;
    }
    return poll_gamepad(inputState->primary_gamepad_id());
}

std::optional<DialTypePendingInput> InputDialType::poll_gamepad(SDL_JoystickID instanceId)
{
    auto it = dialByGamepad.find(instanceId);
    if (it == dialByGamepad.end()) {
        return std::nullopt;
    }
    return it->second.poll();
}

std::vector<SDL_JoystickID> InputDialType::gamepad_ids() const
{
    std::vector<SDL_JoystickID> out;
    out.reserve(dialByGamepad.size());
    for (const auto& [instance_id, dial] : dialByGamepad) {
        (void)dial;
        out.push_back(instance_id);
    }
    return out;
}

void InputDialType::dispatch(SDL_JoystickID instanceId, const DialTypePendingInput& input)
{
    auto it = subscriptionIdsByGamepad.find(instanceId);
    if (it == subscriptionIdsByGamepad.end()) {
        return;
    }

    std::vector<CallbackId> callback_ids;
    callback_ids.reserve(it->second.size());
    for (const CallbackId id : it->second) {
        callback_ids.push_back(id);
    }

    for (const CallbackId id : callback_ids) {
        auto sub_it = subscriptions.find(id);
        if (sub_it == subscriptions.end()) {
            continue;
        }
        const Subscription& subscription = sub_it->second;
        if (subscription.instanceId != instanceId || !subscription.callback) {
            continue;
        }
        CallbackFn callback = subscription.callback;
        callback(instanceId, input);
    }
}

void InputDialType::remove_gamepad_subscriptions(SDL_JoystickID instanceId)
{
    auto ids_it = subscriptionIdsByGamepad.find(instanceId);
    if (ids_it == subscriptionIdsByGamepad.end()) {
        return;
    }

    std::vector<CallbackId> callback_ids;
    callback_ids.reserve(ids_it->second.size());
    for (const CallbackId id : ids_it->second) {
        callback_ids.push_back(id);
    }
    subscriptionIdsByGamepad.erase(ids_it);

    for (const CallbackId id : callback_ids) {
        subscriptions.erase(id);
    }
}
