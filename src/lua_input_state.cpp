#include <sol/sol.hpp>

#include <string>

#include "input_state.h"

namespace {

sol::table create_input_state_table(sol::state_view lua)
{
    sol::table input_state_table = lua.create_table();
    sol::table key_status = lua.create_table();
    key_status["none"] = KeyStatus::None;
    key_status["just-pressed"] = KeyStatus::JustPressed;
    key_status["held"] = KeyStatus::Held;
    key_status["just-released"] = KeyStatus::JustReleased;
    input_state_table["KeyStatus"] = key_status;

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

    sol::usertype<InputState> input_state_type = input_state_table.new_usertype<InputState>(
        "InputState",
        sol::no_constructor);
    input_state_type["keyboard"] = &InputState::keyboardState;
    input_state_type["keyboard-state"] = &InputState::keyboardState;
    input_state_type["mouse"] = &InputState::mouseState;
    input_state_type["mouse-state"] = &InputState::mouseState;
    input_state_type["gamepad-count"] = &InputState::gamepad_count;
    input_state_type["primary-gamepad-id"] = &InputState::primary_gamepad_id;
    input_state_type["begin-frame"] = &InputState::begin_frame;
    input_state_type["on-gamepad-connected"] = &InputState::on_gamepad_connected;
    input_state_type["on-gamepad-disconnected"] = &InputState::on_gamepad_disconnected;
    input_state_type["on-gamepad-button"] = &InputState::on_gamepad_button;
    input_state_type["on-gamepad-axis"] = &InputState::on_gamepad_axis;
    input_state_type["gamepad"] = sol::property([](InputState& input) {
        return input.primary_gamepad();
    });
    input_state_type["gamepad-state"] = sol::property([](InputState& input) {
        return input.primary_gamepad();
    });
    input_state_type.set_function("gamepad-by-id", [](InputState& input, int instance_id) {
        return input.gamepad_by_id(static_cast<SDL_JoystickID>(instance_id));
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
