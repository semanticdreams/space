#include <sol/sol.hpp>

#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>

#include "input_state.h"

namespace {

const char* pen_event_type_name(InputState::PenEventType type)
{
    switch (type) {
        case InputState::PenEventType::ProximityIn:
            return "proximity-in";
        case InputState::PenEventType::ProximityOut:
            return "proximity-out";
        case InputState::PenEventType::Motion:
            return "motion";
        case InputState::PenEventType::Down:
            return "down";
        case InputState::PenEventType::Up:
            return "up";
        case InputState::PenEventType::ButtonDown:
            return "button-down";
        case InputState::PenEventType::ButtonUp:
            return "button-up";
        case InputState::PenEventType::Axis:
            return "axis";
    }
    return "unknown";
}

void set_pen_axes(sol::table& table, const InputState::PenState& pen)
{
    table["pressure"] = pen.axis(SDL_PEN_AXIS_PRESSURE);
    table["x-tilt"] = pen.axis(SDL_PEN_AXIS_XTILT);
    table["y-tilt"] = pen.axis(SDL_PEN_AXIS_YTILT);
    table["distance"] = pen.axis(SDL_PEN_AXIS_DISTANCE);
    table["rotation"] = pen.axis(SDL_PEN_AXIS_ROTATION);
    table["slider"] = pen.axis(SDL_PEN_AXIS_SLIDER);
    table["tangential-pressure"] = pen.axis(SDL_PEN_AXIS_TANGENTIAL_PRESSURE);
}

sol::table make_pen_event_table(sol::state_view lua, const InputState::PenEventRecord& event)
{
    sol::table out = lua.create_table();
    out["type"] = pen_event_type_name(event.type);
    out["pen-id"] = static_cast<lua_Integer>(event.penId);
    out["x"] = event.x;
    out["y"] = event.y;
    out["xrel"] = event.xrel;
    out["yrel"] = event.yrel;
    out["timestamp"] = event.timestamp;
    out["input-state"] = event.inputState;
    out["eraser"] = event.eraser;
    out["in-range"] = event.inRange;
    out["down"] = event.down;
    out["button"] = static_cast<int>(event.button);
    out["button-down"] = event.buttonDown;
    out["axis"] = static_cast<int>(event.axis);
    out["value"] = event.value;
    out["pressure"] = event.axes[SDL_PEN_AXIS_PRESSURE];
    out["x-tilt"] = event.axes[SDL_PEN_AXIS_XTILT];
    out["y-tilt"] = event.axes[SDL_PEN_AXIS_YTILT];
    out["distance"] = event.axes[SDL_PEN_AXIS_DISTANCE];
    out["rotation"] = event.axes[SDL_PEN_AXIS_ROTATION];
    out["slider"] = event.axes[SDL_PEN_AXIS_SLIDER];
    out["tangential-pressure"] = event.axes[SDL_PEN_AXIS_TANGENTIAL_PRESSURE];
    return out;
}

sol::table create_input_state_table(sol::state_view lua)
{
    sol::table input_state_table = lua.create_table();
    sol::table key_status = lua.create_table();
    key_status["none"] = KeyStatus::None;
    key_status["just-pressed"] = KeyStatus::JustPressed;
    key_status["held"] = KeyStatus::Held;
    key_status["just-released"] = KeyStatus::JustReleased;
    input_state_table["KeyStatus"] = key_status;
    sol::table pen_axis = lua.create_table();
    pen_axis["pressure"] = static_cast<int>(SDL_PEN_AXIS_PRESSURE);
    pen_axis["x-tilt"] = static_cast<int>(SDL_PEN_AXIS_XTILT);
    pen_axis["y-tilt"] = static_cast<int>(SDL_PEN_AXIS_YTILT);
    pen_axis["distance"] = static_cast<int>(SDL_PEN_AXIS_DISTANCE);
    pen_axis["rotation"] = static_cast<int>(SDL_PEN_AXIS_ROTATION);
    pen_axis["slider"] = static_cast<int>(SDL_PEN_AXIS_SLIDER);
    pen_axis["tangential-pressure"] = static_cast<int>(SDL_PEN_AXIS_TANGENTIAL_PRESSURE);
    input_state_table["PenAxis"] = pen_axis;
    sol::table pen_input_flags = lua.create_table();
    pen_input_flags["down"] = SDL_PEN_INPUT_DOWN;
    pen_input_flags["button-1"] = SDL_PEN_INPUT_BUTTON_1;
    pen_input_flags["button-2"] = SDL_PEN_INPUT_BUTTON_2;
    pen_input_flags["button-3"] = SDL_PEN_INPUT_BUTTON_3;
    pen_input_flags["button-4"] = SDL_PEN_INPUT_BUTTON_4;
    pen_input_flags["button-5"] = SDL_PEN_INPUT_BUTTON_5;
    pen_input_flags["eraser-tip"] = SDL_PEN_INPUT_ERASER_TIP;
    input_state_table["PenInputFlags"] = pen_input_flags;

    input_state_table.new_usertype<KeyboardState>(
        "KeyboardState",
        sol::no_constructor,
        "is-up", &KeyboardState::isUp,
        "is-free", &KeyboardState::isFree,
        "is-just-pressed", &KeyboardState::isJustPressed,
        "is-down", &KeyboardState::isDown,
        "is-held", &KeyboardState::isHeld,
        "is-just-released", &KeyboardState::isJustReleased,
        "key-state", &KeyboardState::getKeyState);

    input_state_table.new_usertype<MouseState>(
        "MouseState",
        sol::no_constructor,
        "x", &MouseState::x,
        "y", &MouseState::y,
        "xrel", &MouseState::xrel,
        "yrel", &MouseState::yrel,
        "wheel-x", &MouseState::wheelX,
        "wheel-y", &MouseState::wheelY,
        "is-up", &MouseState::isUp,
        "is-free", &MouseState::isFree,
        "is-just-pressed", &MouseState::isJustPressed,
        "is-down", &MouseState::isDown,
        "is-held", &MouseState::isHeld,
        "is-just-released", &MouseState::isJustReleased,
        "button-state", &MouseState::getButtonState);

    input_state_table.new_usertype<GamepadState>(
        "GamepadState",
        sol::no_constructor,
        "connected", &GamepadState::connected,
        "instance-id", &GamepadState::instanceId,
        "device-index", &GamepadState::deviceIndex,
        "update-timestamp", &GamepadState::updateTimestamp,
        "axis", &GamepadState::axis,
        "is-up", &GamepadState::isUp,
        "is-free", &GamepadState::isFree,
        "is-just-pressed", &GamepadState::isJustPressed,
        "is-down", &GamepadState::isDown,
        "is-held", &GamepadState::isHeld,
        "is-just-released", &GamepadState::isJustReleased,
        "button-state", &GamepadState::getButtonState);

    input_state_table.new_usertype<InputState::TouchContactId>(
        "TouchContactId",
        sol::no_constructor,
        "touch-id", &InputState::TouchContactId::touchId,
        "finger-id", &InputState::TouchContactId::fingerId);

    input_state_table.new_usertype<InputState::TouchPointState>(
        "TouchPointState",
        sol::no_constructor,
        "touch-id", &InputState::TouchPointState::touchId,
        "finger-id", &InputState::TouchPointState::fingerId,
        "x", &InputState::TouchPointState::x,
        "y", &InputState::TouchPointState::y,
        "dx", &InputState::TouchPointState::dx,
        "dy", &InputState::TouchPointState::dy,
        "pressure", &InputState::TouchPointState::pressure,
        "update-timestamp", &InputState::TouchPointState::updateTimestamp,
        "is-up", &InputState::TouchPointState::isUp,
        "is-free", &InputState::TouchPointState::isFree,
        "is-just-pressed", &InputState::TouchPointState::isJustPressed,
        "is-down", &InputState::TouchPointState::isDown,
        "is-held", &InputState::TouchPointState::isHeld,
        "is-just-released", &InputState::TouchPointState::isJustReleased,
        "touch-state", &InputState::TouchPointState::getTouchState);

    input_state_table.new_usertype<InputState::PenState>(
        "PenState",
        sol::no_constructor,
        "pen-id", &InputState::PenState::penId,
        "x", &InputState::PenState::x,
        "y", &InputState::PenState::y,
        "xrel", &InputState::PenState::xrel,
        "yrel", &InputState::PenState::yrel,
        "update-timestamp", &InputState::PenState::updateTimestamp,
        "input-state", &InputState::PenState::inputState,
        "eraser", &InputState::PenState::eraser,
        "is-in-range", &InputState::PenState::isInRange,
        "is-just-entered", &InputState::PenState::isJustEntered,
        "is-hovering", &InputState::PenState::isHovering,
        "is-just-left", &InputState::PenState::isJustLeft,
        "is-up", &InputState::PenState::isUp,
        "is-free", &InputState::PenState::isFree,
        "is-just-pressed", &InputState::PenState::isJustPressed,
        "is-down", &InputState::PenState::isDown,
        "is-held", &InputState::PenState::isHeld,
        "is-just-released", &InputState::PenState::isJustReleased,
        "is-button-down", &InputState::PenState::isButtonDown,
        "button-state", &InputState::PenState::getButtonState,
        "proximity-state", &InputState::PenState::getProximityState,
        "tip-state", &InputState::PenState::getTipState,
        "has-axis", &InputState::PenState::hasAxis,
        "axis", [](const InputState::PenState& pen, int axis) {
            return pen.axis(static_cast<SDL_PenAxis>(axis));
        },
        "pressure", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_PRESSURE);
        }),
        "x-tilt", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_XTILT);
        }),
        "y-tilt", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_YTILT);
        }),
        "distance", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_DISTANCE);
        }),
        "rotation", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_ROTATION);
        }),
        "slider", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_SLIDER);
        }),
        "tangential-pressure", sol::property([](const InputState::PenState& pen) {
            return pen.axis(SDL_PEN_AXIS_TANGENTIAL_PRESSURE);
        }));

    sol::usertype<InputState> input_state_type = input_state_table.new_usertype<InputState>(
        "InputState",
        sol::no_constructor);
    input_state_type["keyboard"] = &InputState::keyboardState;
    input_state_type["keyboard-state"] = &InputState::keyboardState;
    input_state_type["mouse"] = &InputState::mouseState;
    input_state_type["mouse-state"] = &InputState::mouseState;
    input_state_type["gamepad-count"] = &InputState::gamepad_count;
    input_state_type["primary-gamepad-id"] = &InputState::primary_gamepad_id;
    input_state_type["touch-count"] = &InputState::touch_count;
    input_state_type["pen-count"] = &InputState::pen_count;
    input_state_type["begin-frame"] = &InputState::begin_frame;
    input_state_type["on-gamepad-connected"] = &InputState::on_gamepad_connected;
    input_state_type["on-gamepad-disconnected"] = &InputState::on_gamepad_disconnected;
    input_state_type["on-gamepad-button"] = &InputState::on_gamepad_button;
    input_state_type["on-gamepad-axis"] = &InputState::on_gamepad_axis;
    input_state_type["on-touch-down"] = &InputState::on_touch_down;
    input_state_type["on-touch-motion"] = &InputState::on_touch_motion;
    input_state_type["on-touch-up"] = &InputState::on_touch_up;
    input_state_type["on-pen-proximity-in"] = &InputState::on_pen_proximity_in;
    input_state_type["on-pen-proximity-out"] = &InputState::on_pen_proximity_out;
    input_state_type["on-pen-motion"] = &InputState::on_pen_motion;
    input_state_type["on-pen-down"] = &InputState::on_pen_down;
    input_state_type["on-pen-up"] = &InputState::on_pen_up;
    input_state_type["on-pen-button"] = &InputState::on_pen_button;
    input_state_type["on-pen-axis"] = &InputState::on_pen_axis;
    input_state_type["gamepad"] = sol::property([](InputState& input) {
        return input.primary_gamepad();
    });
    input_state_type["gamepad-state"] = sol::property([](InputState& input) {
        return input.primary_gamepad();
    });
    input_state_type["touch"] = sol::property([](InputState& input) {
        return input.primary_touch();
    });
    input_state_type["touch-state"] = sol::property([](InputState& input) {
        return input.primary_touch();
    });
    input_state_type["pen"] = sol::property([](InputState& input) {
        return input.primary_pen();
    });
    input_state_type["pen-state"] = sol::property([](InputState& input) {
        return input.primary_pen();
    });
    input_state_type.set_function("primary-touch-id", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        const std::optional<InputState::TouchContactId> id = input.primary_touch_id();
        if (!id) {
            return sol::make_object(lua, sol::nil);
        }
        return sol::make_object(lua, *id);
    });
    input_state_type.set_function("gamepad-by-id", [](InputState& input, int instance_id) {
        return input.gamepad_by_id(static_cast<SDL_JoystickID>(instance_id));
    });
    input_state_type.set_function("primary-pen-id", [](InputState& input) {
        return static_cast<lua_Integer>(input.primary_pen_id());
    });
    input_state_type.set_function("gamepad-ids", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        sol::table ids = lua.create_table();
        int index = 1;
        for (const SDL_JoystickID instance_id : input.gamepad_ids()) {
            ids[index] = instance_id;
            ++index;
        }
        return ids;
    });
    input_state_type.set_function("gamepads", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        sol::table gamepads = lua.create_table();
        for (const SDL_JoystickID instance_id : input.gamepad_ids()) {
            gamepads[instance_id] = input.gamepad_by_id(instance_id);
        }
        return gamepads;
    });
    input_state_type.set_function("touch-by-id", [](InputState& input, std::int64_t touch_id, std::int64_t finger_id) {
        return input.touch_by_id(static_cast<SDL_TouchID>(touch_id), static_cast<SDL_FingerID>(finger_id));
    });
    input_state_type.set_function("touch-ids", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        sol::table ids = lua.create_table();
        int index = 1;
        for (const InputState::TouchContactId& id : input.touch_ids()) {
            ids[index] = id;
            ++index;
        }
        return ids;
    });
    input_state_type.set_function("touches", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        sol::table touches = lua.create_table();
        int index = 1;
        for (const InputState::TouchContactId& id : input.touch_ids()) {
            touches[index] = input.touch_by_id(id.touchId, id.fingerId);
            ++index;
        }
        return touches;
    });
    input_state_type.set_function("pen-by-id", [](InputState& input, std::int64_t pen_id) {
        return input.pen_by_id(static_cast<SDL_PenID>(pen_id));
    });
    input_state_type.set_function("pen-ids", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        sol::table ids = lua.create_table();
        int index = 1;
        for (const SDL_PenID pen_id : input.pen_ids()) {
            ids[index] = static_cast<lua_Integer>(pen_id);
            ++index;
        }
        return ids;
    });
    input_state_type.set_function("pens", [](InputState& input, sol::this_state state) {
        sol::state_view lua(state);
        sol::table pens = lua.create_table();
        int index = 1;
        for (const SDL_PenID pen_id : input.pen_ids()) {
            pens[index] = input.pen_by_id(pen_id);
            ++index;
        }
        return pens;
    });
    input_state_type.set_function("pen-events", [](InputState& input,
                                                   std::int64_t pen_id,
                                                   sol::this_state state,
                                                   sol::optional<int> max_count) {
        sol::state_view lua(state);
        sol::table events = lua.create_table();
        const InputState::PenState* pen = input.pen_by_id(static_cast<SDL_PenID>(pen_id));
        if (!pen) {
            return events;
        }
        int limit = max_count.value_or(static_cast<int>(pen->recentEvents.size()));
        if (limit < 0) {
            limit = 0;
        }
        const int total = static_cast<int>(pen->recentEvents.size());
        const int start = std::max(0, total - limit);
        int index = 1;
        for (int event_index = start; event_index < total; ++event_index) {
            events[index] = make_pen_event_table(lua, pen->recentEvents[static_cast<std::size_t>(event_index)]);
            ++index;
        }
        return events;
    });
    input_state_type.set_function("pen-axis-values", [](InputState& input,
                                                        std::int64_t pen_id,
                                                        sol::this_state state) {
        sol::state_view lua(state);
        sol::table values = lua.create_table();
        const InputState::PenState* pen = input.pen_by_id(static_cast<SDL_PenID>(pen_id));
        if (!pen) {
            return values;
        }
        set_pen_axes(values, *pen);
        return values;
    });
    input_state_table.set_function("InputState", []() {
        return InputState();
    });
    return input_state_table;
}

} // namespace

void lua_bind_input_state(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("input-state", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_input_state_table(lua);
    });
}
