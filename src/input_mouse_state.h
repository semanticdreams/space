#ifndef INPUT_MOUSE_STATE_H
#define INPUT_MOUSE_STATE_H

#ifdef __linux__
#include <SDL2/SDL.h>
#elif _WIN32

#include <SDL.h>

#endif

#include "input_keyboard_state.h"

class MouseState {
public:
    static constexpr int MAX_BUTTONS = 8;

    int x {0};
    int y {0};
    int xrel {0};
    int yrel {0};
    int wheelX {0};
    int wheelY {0};

    void begin_frame();
    void update_from_mask(Uint32 mask);
    void set_motion(int newX, int newY, int deltaX, int deltaY);
    void add_wheel(int deltaX, int deltaY);
    void set_button(Uint8 button, bool pressed);

    [[nodiscard]] KeyStatus getButtonState(Uint8 button) const;
    [[nodiscard]] bool isUp(Uint8 button) const;
    [[nodiscard]] bool isFree(Uint8 button) const;
    [[nodiscard]] bool isJustPressed(Uint8 button) const;
    [[nodiscard]] bool isDown(Uint8 button) const;
    [[nodiscard]] bool isHeld(Uint8 button) const;
    [[nodiscard]] bool isJustReleased(Uint8 button) const;

private:
    Uint8 currentButtons[MAX_BUTTONS] {0};
    Uint8 previousButtons[MAX_BUTTONS] {0};

    [[nodiscard]] size_t index_for_button(Uint8 button) const;
};

#endif
