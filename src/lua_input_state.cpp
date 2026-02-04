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

    sol::usertype<InputState> input_state_type = input_state_table.new_usertype<InputState>(
        "InputState",
        sol::no_constructor);
    input_state_type["keyboard"] = &InputState::keyboardState;
    input_state_type["keyboard-state"] = &InputState::keyboardState;
    input_state_type["mouse"] = &InputState::mouseState;
    input_state_type["mouse-state"] = &InputState::mouseState;
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
