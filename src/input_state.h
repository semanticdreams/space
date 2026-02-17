#ifndef INPUT_STATE_H
#define INPUT_STATE_H

#include <memory>
#include <unordered_map>
#include <vector>

#include "input_game_controller_state.h"
#include "input_keyboard_state.h"
#include "input_mouse_state.h"

struct InputState
{
    KeyboardState keyboardState;
    MouseState mouseState;
    std::unordered_map<SDL_JoystickID, std::shared_ptr<GameControllerState>> controllerStates;
    SDL_JoystickID primaryControllerId {-1};

    InputState();

    void begin_frame();
    void on_controller_connected(Sint32 deviceIndex, SDL_JoystickID instanceId, Uint32 timestamp);
    void on_controller_disconnected(SDL_JoystickID instanceId, Uint32 timestamp);
    void on_controller_button(Uint8 button, bool pressed, SDL_JoystickID instanceId, Uint32 timestamp);
    void on_controller_axis(Uint8 axis, float value, SDL_JoystickID instanceId, Uint32 timestamp);

    [[nodiscard]] size_t controller_count() const;
    [[nodiscard]] SDL_JoystickID primary_controller_id() const;
    [[nodiscard]] const GameControllerState* primary_controller() const;
    [[nodiscard]] GameControllerState* primary_controller();
    [[nodiscard]] const GameControllerState* controller_by_id(SDL_JoystickID instanceId) const;
    [[nodiscard]] GameControllerState* controller_by_id(SDL_JoystickID instanceId);
    [[nodiscard]] std::vector<SDL_JoystickID> controller_ids() const;

private:
    std::shared_ptr<GameControllerState> ensure_controller(SDL_JoystickID instanceId);
    void assign_primary_if_missing(SDL_JoystickID preferredId);
};

#endif
