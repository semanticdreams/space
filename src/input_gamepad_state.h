#ifndef INPUT_GAME_CONTROLLER_STATE_H
#define INPUT_GAME_CONTROLLER_STATE_H

#include <SDL3/SDL.h>

#include "input_keyboard_state.h"

class GamepadState
{
public:
    static constexpr int MAX_BUTTONS = SDL_GAMEPAD_BUTTON_COUNT;
    static constexpr int MAX_AXES = SDL_GAMEPAD_AXIS_COUNT;

    bool connected {false};
    SDL_JoystickID instanceId {0};
    Sint32 deviceIndex {-1};
    Uint64 updateTimestamp {0};
    float axes[MAX_AXES] {0.0F};

    void begin_frame();
    void connect(Sint32 newDeviceIndex, SDL_JoystickID newInstanceId, Uint64 timestamp);
    void disconnect(SDL_JoystickID removedInstanceId, Uint64 timestamp);
    void set_button(Uint8 button, bool pressed, SDL_JoystickID sourceInstanceId, Uint64 timestamp);
    void set_axis(Uint8 axis, float value, SDL_JoystickID sourceInstanceId, Uint64 timestamp);

    [[nodiscard]] KeyStatus getButtonState(Uint8 button) const;
    [[nodiscard]] bool isUp(Uint8 button) const;
    [[nodiscard]] bool isFree(Uint8 button) const;
    [[nodiscard]] bool isJustPressed(Uint8 button) const;
    [[nodiscard]] bool isDown(Uint8 button) const;
    [[nodiscard]] bool isHeld(Uint8 button) const;
    [[nodiscard]] bool isJustReleased(Uint8 button) const;
    [[nodiscard]] float axis(Uint8 axisIndex) const;

private:
    Uint8 currentButtons[MAX_BUTTONS] {0};
    Uint8 previousButtons[MAX_BUTTONS] {0};

    [[nodiscard]] size_t index_for_button(Uint8 button) const;
    [[nodiscard]] size_t index_for_axis(Uint8 axisIndex) const;
};

#endif
