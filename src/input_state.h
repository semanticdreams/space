#ifndef INPUT_STATE_H
#define INPUT_STATE_H

#include "input_keyboard_state.h"
#include "input_mouse_state.h"

struct InputState
{
    KeyboardState keyboardState;
    MouseState mouseState;

    InputState();
};

#endif
