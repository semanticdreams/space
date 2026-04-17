#include "input_state.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>

namespace {

KeyStatus key_status_for_transition(bool current, bool previous)
{
    if (!previous) {
        return current ? JustPressed : None;
    }
    return current ? Held : JustReleased;
}

std::size_t pen_button_index(Uint8 button)
{
    return button > 0 ? static_cast<std::size_t>(button - 1) : InputState::PenButtonCount;
}

SDL_PenInputFlags pen_button_flag(Uint8 button)
{
    switch (button) {
        case 1:
            return SDL_PEN_INPUT_BUTTON_1;
        case 2:
            return SDL_PEN_INPUT_BUTTON_2;
        case 3:
            return SDL_PEN_INPUT_BUTTON_3;
        case 4:
            return SDL_PEN_INPUT_BUTTON_4;
        case 5:
            return SDL_PEN_INPUT_BUTTON_5;
        default:
            return 0;
    }
}

void sync_pen_buttons_from_state(InputState::PenState& pen)
{
    for (std::size_t index = 0; index < InputState::PenButtonCount; ++index) {
        const Uint8 button = static_cast<Uint8>(index + 1);
        pen.currentButtons[index] = (pen.inputState & pen_button_flag(button)) != 0;
    }
}

void clear_pen_buttons(InputState::PenState& pen)
{
    pen.currentButtons.fill(false);
}

void update_pen_position(InputState::PenState& pen, float newX, float newY)
{
    if (pen.hasPosition) {
        pen.xrel = newX - pen.x;
        pen.yrel = newY - pen.y;
    } else {
        pen.xrel = 0.0F;
        pen.yrel = 0.0F;
        pen.hasPosition = true;
    }
    pen.x = newX;
    pen.y = newY;
}

float pen_axis_value(const std::array<float, SDL_PEN_AXIS_COUNT>& axes, SDL_PenAxis axis)
{
    const auto index = static_cast<std::size_t>(axis);
    if (index >= axes.size()) {
        return 0.0F;
    }
    return axes[index];
}

} // namespace

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
    return key_status_for_transition(currentDown, previousDown);
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

void InputState::PenState::begin_frame()
{
    previousInRange = currentInRange;
    previousDown = currentDown;
    previousButtons = currentButtons;
    xrel = 0.0F;
    yrel = 0.0F;
}

void InputState::PenState::set_proximity(bool inRange, Uint64 timestamp)
{
    xrel = 0.0F;
    yrel = 0.0F;
    updateTimestamp = timestamp;
    currentInRange = inRange;
    if (inRange) {
        hasPosition = false;
        inputState = 0;
        seenAxesMask = 0;
        axes.fill(0.0F);
    }
    currentDown = false;
    if (!inRange) {
        inputState = 0;
        eraser = false;
        hasPosition = false;
        seenAxesMask = 0;
        axes.fill(0.0F);
        clear_pen_buttons(*this);
    }
}

void InputState::PenState::set_motion(float newX,
                                      float newY,
                                      SDL_PenInputFlags newInputState,
                                      Uint64 timestamp)
{
    update_pen_position(*this, newX, newY);
    updateTimestamp = timestamp;
    inputState = newInputState;
    currentInRange = true;
    currentDown = (newInputState & SDL_PEN_INPUT_DOWN) != 0;
    eraser = (newInputState & SDL_PEN_INPUT_ERASER_TIP) != 0;
    sync_pen_buttons_from_state(*this);
}

void InputState::PenState::set_touch(float newX,
                                     float newY,
                                     bool newEraser,
                                     bool down,
                                     SDL_PenInputFlags newInputState,
                                     Uint64 timestamp)
{
    update_pen_position(*this, newX, newY);
    updateTimestamp = timestamp;
    inputState = newInputState;
    currentInRange = true;
    currentDown = down;
    eraser = newEraser;
    sync_pen_buttons_from_state(*this);
}

void InputState::PenState::set_button(float newX,
                                      float newY,
                                      Uint8 button,
                                      bool down,
                                      SDL_PenInputFlags newInputState,
                                      Uint64 timestamp)
{
    update_pen_position(*this, newX, newY);
    updateTimestamp = timestamp;
    inputState = newInputState;
    currentInRange = true;
    currentDown = (newInputState & SDL_PEN_INPUT_DOWN) != 0;
    eraser = (newInputState & SDL_PEN_INPUT_ERASER_TIP) != 0;
    sync_pen_buttons_from_state(*this);
    const std::size_t index = pen_button_index(button);
    if (index < currentButtons.size()) {
        currentButtons[index] = down;
    }
}

void InputState::PenState::set_axis(float newX,
                                    float newY,
                                    SDL_PenAxis axisId,
                                    float axisValue,
                                    SDL_PenInputFlags newInputState,
                                    Uint64 timestamp)
{
    update_pen_position(*this, newX, newY);
    updateTimestamp = timestamp;
    inputState = newInputState;
    currentInRange = true;
    currentDown = (newInputState & SDL_PEN_INPUT_DOWN) != 0;
    eraser = (newInputState & SDL_PEN_INPUT_ERASER_TIP) != 0;
    sync_pen_buttons_from_state(*this);
    const auto index = static_cast<std::size_t>(axisId);
    if (index < axes.size()) {
        axes[index] = axisValue;
        seenAxesMask |= static_cast<Uint32>(1u << index);
    }
}

void InputState::PenState::push_event(const PenEventRecord& record)
{
    if (recentEvents.size() >= PenEventHistoryLimit) {
        recentEvents.erase(recentEvents.begin());
    }
    recentEvents.push_back(record);
}

KeyStatus InputState::PenState::getProximityState() const
{
    return key_status_for_transition(currentInRange, previousInRange);
}

KeyStatus InputState::PenState::getTipState() const
{
    return key_status_for_transition(currentDown, previousDown);
}

KeyStatus InputState::PenState::getButtonState(Uint8 button) const
{
    const std::size_t index = pen_button_index(button);
    if (index >= currentButtons.size()) {
        return None;
    }
    return key_status_for_transition(currentButtons[index], previousButtons[index]);
}

bool InputState::PenState::isInRange() const
{
    return currentInRange;
}

bool InputState::PenState::isJustEntered() const
{
    return getProximityState() == JustPressed;
}

bool InputState::PenState::isHovering() const
{
    return currentInRange && !currentDown;
}

bool InputState::PenState::isJustLeft() const
{
    return getProximityState() == JustReleased;
}

bool InputState::PenState::isUp() const
{
    return !isDown();
}

bool InputState::PenState::isFree() const
{
    return getTipState() == None;
}

bool InputState::PenState::isJustPressed() const
{
    return getTipState() == JustPressed;
}

bool InputState::PenState::isDown() const
{
    return currentDown;
}

bool InputState::PenState::isHeld() const
{
    return getTipState() == Held;
}

bool InputState::PenState::isJustReleased() const
{
    return getTipState() == JustReleased;
}

bool InputState::PenState::isButtonDown(Uint8 button) const
{
    const std::size_t index = pen_button_index(button);
    return index < currentButtons.size() ? currentButtons[index] : false;
}

bool InputState::PenState::hasAxis(SDL_PenAxis axisId) const
{
    const auto index = static_cast<std::size_t>(axisId);
    if (index >= axes.size()) {
        return false;
    }
    return (seenAxesMask & static_cast<Uint32>(1u << index)) != 0;
}

float InputState::PenState::axis(SDL_PenAxis axisId) const
{
    return pen_axis_value(axes, axisId);
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

    for (auto it = penStates.begin(); it != penStates.end();) {
        if (!it->second) {
            it = penStates.erase(it);
            continue;
        }
        if (!it->second->currentInRange && !it->second->previousInRange && !it->second->currentDown && !it->second->previousDown) {
            if (primaryPenId == it->first) {
                primaryPenId = 0;
            }
            it = penStates.erase(it);
            continue;
        }
        it->second->begin_frame();
        ++it;
    }

    if (primaryPenId != 0 && (!pen_by_id(primaryPenId) || !pen_by_id(primaryPenId)->currentInRange)) {
        primaryPenId = 0;
    }
    assign_primary_pen_if_missing(0);
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

void InputState::on_pen_proximity_in(SDL_PenID penId, Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_proximity(true, timestamp);
    pen->push_event(PenEventRecord {PenEventType::ProximityIn,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    0,
                                    false,
                                    SDL_PEN_AXIS_PRESSURE,
                                    0.0F,
                                    pen->axes});
    primaryPenId = penId;
}

void InputState::on_pen_proximity_out(SDL_PenID penId, Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_proximity(false, timestamp);
    pen->push_event(PenEventRecord {PenEventType::ProximityOut,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    0,
                                    false,
                                    SDL_PEN_AXIS_PRESSURE,
                                    0.0F,
                                    pen->axes});
    if (primaryPenId == penId) {
        primaryPenId = 0;
        assign_primary_pen_if_missing(0);
    }
}

void InputState::on_pen_motion(SDL_PenID penId,
                               float x,
                               float y,
                               SDL_PenInputFlags inputStateValue,
                               Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_motion(x, y, inputStateValue, timestamp);
    pen->push_event(PenEventRecord {PenEventType::Motion,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    0,
                                    false,
                                    SDL_PEN_AXIS_PRESSURE,
                                    0.0F,
                                    pen->axes});
    primaryPenId = penId;
}

void InputState::on_pen_down(SDL_PenID penId,
                             float x,
                             float y,
                             bool eraser,
                             SDL_PenInputFlags inputStateValue,
                             Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_touch(x, y, eraser, true, inputStateValue, timestamp);
    pen->push_event(PenEventRecord {PenEventType::Down,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    0,
                                    false,
                                    SDL_PEN_AXIS_PRESSURE,
                                    0.0F,
                                    pen->axes});
    primaryPenId = penId;
}

void InputState::on_pen_up(SDL_PenID penId,
                           float x,
                           float y,
                           bool eraser,
                           SDL_PenInputFlags inputStateValue,
                           Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_touch(x, y, eraser, false, inputStateValue, timestamp);
    pen->push_event(PenEventRecord {PenEventType::Up,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    0,
                                    false,
                                    SDL_PEN_AXIS_PRESSURE,
                                    0.0F,
                                    pen->axes});
    primaryPenId = penId;
}

void InputState::on_pen_button(SDL_PenID penId,
                               float x,
                               float y,
                               Uint8 button,
                               bool down,
                               SDL_PenInputFlags inputStateValue,
                               Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_button(x, y, button, down, inputStateValue, timestamp);
    pen->push_event(PenEventRecord {down ? PenEventType::ButtonDown : PenEventType::ButtonUp,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    button,
                                    down,
                                    SDL_PEN_AXIS_PRESSURE,
                                    0.0F,
                                    pen->axes});
    primaryPenId = penId;
}

void InputState::on_pen_axis(SDL_PenID penId,
                             float x,
                             float y,
                             SDL_PenAxis axisId,
                             float value,
                             SDL_PenInputFlags inputStateValue,
                             Uint64 timestamp)
{
    const std::shared_ptr<PenState> pen = ensure_pen(penId);
    pen->penId = penId;
    pen->set_axis(x, y, axisId, value, inputStateValue, timestamp);
    pen->push_event(PenEventRecord {PenEventType::Axis,
                                    penId,
                                    pen->x,
                                    pen->y,
                                    pen->xrel,
                                    pen->yrel,
                                    timestamp,
                                    pen->inputState,
                                    pen->eraser,
                                    pen->currentInRange,
                                    pen->currentDown,
                                    0,
                                    false,
                                    axisId,
                                    value,
                                    pen->axes});
    primaryPenId = penId;
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

size_t InputState::pen_count() const
{
    size_t count = 0;
    for (const auto& [pen_id, pen] : penStates) {
        (void)pen_id;
        if (pen && pen->currentInRange) {
            ++count;
        }
    }
    return count;
}

SDL_PenID InputState::primary_pen_id() const
{
    return primaryPenId;
}

const InputState::PenState* InputState::primary_pen() const
{
    return pen_by_id(primaryPenId);
}

InputState::PenState* InputState::primary_pen()
{
    return pen_by_id(primaryPenId);
}

const InputState::PenState* InputState::pen_by_id(SDL_PenID penId) const
{
    const auto it = penStates.find(penId);
    if (it == penStates.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

InputState::PenState* InputState::pen_by_id(SDL_PenID penId)
{
    auto it = penStates.find(penId);
    if (it == penStates.end() || !it->second) {
        return nullptr;
    }
    return it->second.get();
}

std::vector<SDL_PenID> InputState::pen_ids() const
{
    std::vector<SDL_PenID> ids;
    ids.reserve(penStates.size());
    for (const auto& [pen_id, pen] : penStates) {
        if (pen && pen->currentInRange) {
            ids.push_back(pen_id);
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

std::shared_ptr<InputState::PenState> InputState::ensure_pen(SDL_PenID penId)
{
    auto it = penStates.find(penId);
    if (it != penStates.end() && it->second) {
        return it->second;
    }
    auto pen = std::make_shared<PenState>();
    penStates[penId] = pen;
    return pen;
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

void InputState::assign_primary_pen_if_missing(SDL_PenID preferredId)
{
    PenState* primaryPen = primaryPenId != 0 ? pen_by_id(primaryPenId) : nullptr;
    if (primaryPen && primaryPen->currentInRange) {
        return;
    }
    if (preferredId != 0) {
        PenState* preferredPen = pen_by_id(preferredId);
        if (preferredPen && preferredPen->currentInRange) {
            primaryPenId = preferredId;
            return;
        }
    }
    for (const auto& [pen_id, pen] : penStates) {
        if (pen && pen->currentInRange) {
            primaryPenId = pen_id;
            return;
        }
    }
    primaryPenId = 0;
}
