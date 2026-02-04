#include "input_state.h"

#include <cstring>

InputState::InputState()
{
    keyboardState.currentValue = nullptr;
    std::memset(keyboardState.previousValue, 0, SDL_NUM_SCANCODES);
}
