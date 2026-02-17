#include "input_dial_type.h"

#ifdef __linux__
#include <SDL2/SDL.h>
#elif _WIN32

#include <SDL.h>

#endif

#include <unordered_set>

InputDialType::InputDialType(InputState& inputStateRef)
    : inputState(&inputStateRef)
{
}

void InputDialType::reset()
{
    for (auto& [instance_id, dial] : dialByController) {
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
    const std::vector<SDL_JoystickID> ids = inputState->controller_ids();
    std::unordered_set<SDL_JoystickID> connected(ids.begin(), ids.end());

    for (auto it = dialByController.begin(); it != dialByController.end();) {
        if (connected.count(it->first) == 0) {
            activeControllers.erase(it->first);
            remove_controller_subscriptions(it->first);
            it = dialByController.erase(it);
        } else {
            ++it;
        }
    }

    for (const SDL_JoystickID instance_id : ids) {
        const GameControllerState* controller = inputState->controller_by_id(instance_id);
        if (!controller) {
            continue;
        }
        DialType& dial = dialByController[instance_id];
        if (dial.update(controller->axis(SDL_CONTROLLER_AXIS_LEFTX),
                        controller->axis(SDL_CONTROLLER_AXIS_LEFTY),
                        controller->axis(SDL_CONTROLLER_AXIS_RIGHTX),
                        controller->axis(SDL_CONTROLLER_AXIS_RIGHTY))) {
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
    return update_controller(inputState->primary_controller_id());
}

bool InputDialType::update_controller(SDL_JoystickID instanceId)
{
    if (!inputState || instanceId == -1) {
        return false;
    }
    const GameControllerState* controller = inputState->controller_by_id(instanceId);
    if (!controller) {
        deactivate_controller(instanceId);
        return false;
    }
    DialType& dial = dialByController[instanceId];
    return dial.update(controller->axis(SDL_CONTROLLER_AXIS_LEFTX),
                       controller->axis(SDL_CONTROLLER_AXIS_LEFTY),
                       controller->axis(SDL_CONTROLLER_AXIS_RIGHTX),
                       controller->axis(SDL_CONTROLLER_AXIS_RIGHTY));
}

void InputDialType::activate_controller(SDL_JoystickID instanceId)
{
    if (instanceId != -1) {
        activeControllers.insert(instanceId);
    }
}

void InputDialType::deactivate_controller(SDL_JoystickID instanceId)
{
    activeControllers.erase(instanceId);
    dialByController.erase(instanceId);
    remove_controller_subscriptions(instanceId);
}

bool InputDialType::is_controller_active(SDL_JoystickID instanceId) const
{
    return activeControllers.count(instanceId) > 0;
}

bool InputDialType::process_controller(SDL_JoystickID instanceId)
{
    if (!is_controller_active(instanceId)) {
        return false;
    }
    if (!update_controller(instanceId)) {
        deactivate_controller(instanceId);
        return false;
    }
    const std::optional<DialTypePendingInput> pending = poll_controller(instanceId);
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
    subscriptionIdsByController[instanceId].insert(id);
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
    auto ids_it = subscriptionIdsByController.find(instanceId);
    if (ids_it != subscriptionIdsByController.end()) {
        ids_it->second.erase(callbackId);
        if (ids_it->second.empty()) {
            subscriptionIdsByController.erase(ids_it);
        }
    }
    return true;
}

bool InputDialType::has_input() const
{
    if (!inputState) {
        return false;
    }
    const SDL_JoystickID primary_id = inputState->primary_controller_id();
    auto it = dialByController.find(primary_id);
    return it != dialByController.end() && it->second.has_input();
}

bool InputDialType::has_input_for(SDL_JoystickID instanceId) const
{
    auto it = dialByController.find(instanceId);
    return it != dialByController.end() && it->second.has_input();
}

std::optional<DialTypePendingInput> InputDialType::poll_primary()
{
    if (!inputState) {
        return std::nullopt;
    }
    return poll_controller(inputState->primary_controller_id());
}

std::optional<DialTypePendingInput> InputDialType::poll_controller(SDL_JoystickID instanceId)
{
    auto it = dialByController.find(instanceId);
    if (it == dialByController.end()) {
        return std::nullopt;
    }
    return it->second.poll();
}

std::vector<SDL_JoystickID> InputDialType::controller_ids() const
{
    std::vector<SDL_JoystickID> out;
    out.reserve(dialByController.size());
    for (const auto& [instance_id, dial] : dialByController) {
        (void)dial;
        out.push_back(instance_id);
    }
    return out;
}

void InputDialType::dispatch(SDL_JoystickID instanceId, const DialTypePendingInput& input)
{
    auto it = subscriptionIdsByController.find(instanceId);
    if (it == subscriptionIdsByController.end()) {
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

void InputDialType::remove_controller_subscriptions(SDL_JoystickID instanceId)
{
    auto ids_it = subscriptionIdsByController.find(instanceId);
    if (ids_it == subscriptionIdsByController.end()) {
        return;
    }

    std::vector<CallbackId> callback_ids;
    callback_ids.reserve(ids_it->second.size());
    for (const CallbackId id : ids_it->second) {
        callback_ids.push_back(id);
    }
    subscriptionIdsByController.erase(ids_it);

    for (const CallbackId id : callback_ids) {
        subscriptions.erase(id);
    }
}
