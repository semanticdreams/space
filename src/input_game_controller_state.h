#ifndef INPUT_GAME_CONTROLLER_STATE_H
#define INPUT_GAME_CONTROLLER_STATE_H

#ifdef __linux__
#include <SDL2/SDL.h>
#elif _WIN32

#include <SDL.h>

#endif

#include "input_keyboard_state.h"

class GameControllerState
{
public:
    static constexpr int MAX_BUTTONS = SDL_CONTROLLER_BUTTON_MAX;
    static constexpr int MAX_AXES = SDL_CONTROLLER_AXIS_MAX;

    bool connected {false};
    SDL_JoystickID instanceId {-1};
    Sint32 deviceIndex {-1};
    Uint32 updateTimestamp {0};
    float axes[MAX_AXES] {0.0F};

    void begin_frame();
    void connect(Sint32 newDeviceIndex, SDL_JoystickID newInstanceId, Uint32 timestamp);
    void disconnect(SDL_JoystickID removedInstanceId, Uint32 timestamp);
    void set_button(Uint8 button, bool pressed, SDL_JoystickID sourceInstanceId, Uint32 timestamp);
    void set_axis(Uint8 axis, float value, SDL_JoystickID sourceInstanceId, Uint32 timestamp);

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
