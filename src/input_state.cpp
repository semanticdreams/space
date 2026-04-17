#include "input_state.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>

bool InputState::TouchContactId::valid() const
{
    return touchId != 0 || fingerId != 0;
}

bool InputState::TouchContactId::operator==(const TouchContactId& other) const
{
    return touchId == other.touchId && fingerId == other.fingerId;
}

std::size_t InputState::TouchContactIdHash::operator()(const TouchContactId& id) const
{
    const auto touch_hash = static_cast<std::size_t>(std::hash<std::int64_t> {}(id.touchId));
    const auto finger_hash = static_cast<std::size_t>(std::hash<std::int64_t> {}(id.fingerId));
    return touch_hash ^ (finger_hash + 0x9e3779b97f4a7c15ULL + (touch_hash << 6U) + (touch_hash >> 2U));
}

void InputState::TouchPointState::begin_frame()
{
    previousDown = currentDown;
    dx = 0.0F;
    dy = 0.0F;
}

void InputState::TouchPointState::set_contact(SDL_TouchID newTouchId,
                                              SDL_FingerID newFingerId,
                                              float newX,
                                              float newY,
                                              float deltaX,
                                              float deltaY,
                                              float newPressure,
                                              bool pressed,
                                              Uint64 timestamp)
{
    touchId = newTouchId;
    fingerId = newFingerId;
    x = newX;
    y = newY;
    dx = deltaX;
    dy = deltaY;
    pressure = newPressure;
    updateTimestamp = timestamp;
    currentDown = pressed;
}

KeyStatus InputState::TouchPointState::getTouchState() const
{
    if (!previousDown) {
        return currentDown ? JustPressed : None;
    }
    return currentDown ? Held : JustReleased;
}

bool InputState::TouchPointState::isUp() const
{
    return !isDown();
}

bool InputState::TouchPointState::isFree() const
{
    return getTouchState() == None;
}

bool InputState::TouchPointState::isJustPressed() const
{
    return getTouchState() == JustPressed;
}

bool InputState::TouchPointState::isDown() const
{
    return currentDown;
}

bool InputState::TouchPointState::isHeld() const
{
    return getTouchState() == Held;
}

bool InputState::TouchPointState::isJustReleased() const
{
    return getTouchState() == JustReleased;
}

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

    for (auto it = touchPoints.begin(); it != touchPoints.end();) {
        if (!it->second) {
            it = touchPoints.erase(it);
            continue;
        }
        if (!it->second->currentDown && !it->second->previousDown) {
            if (primaryTouchId && *primaryTouchId == it->first) {
                primaryTouchId.reset();
            }
            it = touchPoints.erase(it);
            continue;
        }
        it->second->begin_frame();
        ++it;
    }

    if (primaryTouchId && (!touch_by_id(*primaryTouchId) || !touch_by_id(*primaryTouchId)->currentDown)) {
        primaryTouchId.reset();
    }
    assign_primary_touch_if_missing(std::nullopt);
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

void InputState::on_touch_down(SDL_TouchID touchId,
                               SDL_FingerID fingerId,
                               float x,
                               float y,
                               float dx,
                               float dy,
                               float pressure,
                               Uint64 timestamp)
{
    const TouchContactId id {touchId, fingerId};
    const std::shared_ptr<TouchPointState> touch = ensure_touch(touchId, fingerId);
    touch->set_contact(touchId, fingerId, x, y, dx, dy, pressure, true, timestamp);
    assign_primary_touch_if_missing(id);
}

void InputState::on_touch_motion(SDL_TouchID touchId,
                                 SDL_FingerID fingerId,
                                 float x,
                                 float y,
                                 float dx,
                                 float dy,
                                 float pressure,
                                 Uint64 timestamp)
{
    const TouchContactId id {touchId, fingerId};
    const std::shared_ptr<TouchPointState> touch = ensure_touch(touchId, fingerId);
    touch->set_contact(touchId, fingerId, x, y, dx, dy, pressure, true, timestamp);
    assign_primary_touch_if_missing(id);
}

void InputState::on_touch_up(SDL_TouchID touchId,
                             SDL_FingerID fingerId,
                             float x,
                             float y,
                             float dx,
                             float dy,
                             float pressure,
                             Uint64 timestamp)
{
    const TouchContactId id {touchId, fingerId};
    const std::shared_ptr<TouchPointState> touch = ensure_touch(touchId, fingerId);
    touch->set_contact(touchId, fingerId, x, y, dx, dy, pressure, false, timestamp);
    if (primaryTouchId && *primaryTouchId == id) {
        primaryTouchId.reset();
        assign_primary_touch_if_missing(std::nullopt);
    }
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

size_t InputState::touch_count() const
{
    size_t count = 0;
    for (const auto& [finger_id, touch] : touchPoints) {
        (void)finger_id;
        if (touch && touch->currentDown) {
            ++count;
        }
    }
    return count;
}

std::optional<InputState::TouchContactId> InputState::primary_touch_id() const
{
    return primaryTouchId;
}

const InputState::TouchPointState* InputState::primary_touch() const
{
    return primaryTouchId ? touch_by_id(*primaryTouchId) : nullptr;
}

InputState::TouchPointState* InputState::primary_touch()
{
    return primaryTouchId ? touch_by_id(*primaryTouchId) : nullptr;
}

const InputState::TouchPointState* InputState::touch_by_id(SDL_TouchID touchId, SDL_FingerID fingerId) const
{
    return touch_by_id(TouchContactId {touchId, fingerId});
}

InputState::TouchPointState* InputState::touch_by_id(SDL_TouchID touchId, SDL_FingerID fingerId)
{
    return touch_by_id(TouchContactId {touchId, fingerId});
}

const InputState::TouchPointState* InputState::touch_by_id(const TouchContactId& id) const
{
    const auto it = touchPoints.find(id);
    if (it == touchPoints.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

InputState::TouchPointState* InputState::touch_by_id(const TouchContactId& id)
{
    auto it = touchPoints.find(id);
    if (it == touchPoints.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

std::vector<InputState::TouchContactId> InputState::touch_ids() const
{
    std::vector<TouchContactId> ids;
    ids.reserve(touchPoints.size());
    for (const auto& [id, touch] : touchPoints) {
        if (touch && touch->currentDown) {
            ids.push_back(id);
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

std::shared_ptr<InputState::TouchPointState> InputState::ensure_touch(SDL_TouchID touchId, SDL_FingerID fingerId)
{
    const TouchContactId id {touchId, fingerId};
    auto it = touchPoints.find(id);
    if (it != touchPoints.end() && it->second) {
        return it->second;
    }
    auto touch = std::make_shared<TouchPointState>();
    touchPoints[id] = touch;
    return touch;
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

void InputState::assign_primary_touch_if_missing(const std::optional<TouchContactId>& preferredId)
{
    TouchPointState* primaryTouch = primaryTouchId ? touch_by_id(*primaryTouchId) : nullptr;
    if (primaryTouch && primaryTouch->currentDown) {
        return;
    }
    if (preferredId && preferredId->valid()) {
        TouchPointState* preferredTouch = touch_by_id(*preferredId);
        if (preferredTouch && preferredTouch->currentDown) {
            primaryTouchId = preferredId;
            return;
        }
    }
    for (const auto& [id, touch] : touchPoints) {
        if (touch && touch->currentDown) {
            primaryTouchId = id;
            return;
        }
    }
    primaryTouchId.reset();
}
