#ifndef INPUT_STATE_H
#define INPUT_STATE_H

#include <memory>
#include <unordered_map>
#include <vector>

#include "input_gamepad_state.h"
#include "input_keyboard_state.h"
#include "input_mouse_state.h"

struct InputState
{
    KeyboardState keyboardState;
    MouseState mouseState;
    std::unordered_map<SDL_JoystickID, std::shared_ptr<GamepadState>> gamepadStates;
    SDL_JoystickID primaryGamepadId {0};

    InputState();

    void begin_frame();
    void on_gamepad_connected(Sint32 deviceIndex, SDL_JoystickID instanceId, Uint64 timestamp);
    void on_gamepad_disconnected(SDL_JoystickID instanceId, Uint64 timestamp);
    void on_gamepad_button(Uint8 button, bool pressed, SDL_JoystickID instanceId, Uint64 timestamp);
    void on_gamepad_axis(Uint8 axis, float value, SDL_JoystickID instanceId, Uint64 timestamp);

    [[nodiscard]] size_t gamepad_count() const;
    [[nodiscard]] SDL_JoystickID primary_gamepad_id() const;
    [[nodiscard]] const GamepadState* primary_gamepad() const;
    [[nodiscard]] GamepadState* primary_gamepad();
    [[nodiscard]] const GamepadState* gamepad_by_id(SDL_JoystickID instanceId) const;
    [[nodiscard]] GamepadState* gamepad_by_id(SDL_JoystickID instanceId);
    [[nodiscard]] std::vector<SDL_JoystickID> gamepad_ids() const;

private:
    std::shared_ptr<GamepadState> ensure_gamepad(SDL_JoystickID instanceId);
    void assign_primary_if_missing(SDL_JoystickID preferredId);
};

#endif
