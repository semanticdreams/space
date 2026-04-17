#include "input_state.h"

#include <cassert>
#include <cstdint>
#include <iostream>

namespace {

void test_pen_lifecycle_tracks_hover_tip_buttons_axes_and_history()
{
    InputState input_state;

    constexpr SDL_PenID pen_id = static_cast<SDL_PenID>(77);

    assert(input_state.pen_count() == 0);
    assert(input_state.primary_pen_id() == 0);
    assert(input_state.primary_pen() == nullptr);

    input_state.on_pen_proximity_in(pen_id, 10);
    assert(input_state.pen_count() == 1);
    assert(input_state.primary_pen_id() == pen_id);

    InputState::PenState* pen = input_state.pen_by_id(pen_id);
    assert(pen != nullptr);
    assert(pen->penId == pen_id);
    assert(pen->isInRange());
    assert(pen->isJustEntered());
    assert(pen->isHovering());
    input_state.begin_frame();
    assert(pen->getProximityState() == Held);

    input_state.on_pen_motion(pen_id, 10.0f, 20.0f, 0, 11);
    assert(pen->x == 10.0f);
    assert(pen->y == 20.0f);

    input_state.on_pen_axis(pen_id, 10.0f, 20.0f, SDL_PEN_AXIS_PRESSURE, 0.6f, 0, 12);
    assert(pen->hasAxis(SDL_PEN_AXIS_PRESSURE));
    assert(pen->axis(SDL_PEN_AXIS_PRESSURE) == 0.6f);

    input_state.on_pen_motion(pen_id, 13.0f, 24.0f, 0, 13);
    assert(pen->x == 13.0f);
    assert(pen->y == 24.0f);
    assert(pen->xrel == 3.0f);
    assert(pen->yrel == 4.0f);

    input_state.on_pen_down(pen_id, 13.0f, 24.0f, false, SDL_PEN_INPUT_DOWN, 14);
    assert(pen->isJustPressed());
    assert(pen->isDown());

    input_state.begin_frame();
    assert(pen->isHeld());

    input_state.on_pen_button(pen_id, 13.0f, 24.0f, 1, true, SDL_PEN_INPUT_DOWN | SDL_PEN_INPUT_BUTTON_1, 15);
    assert(pen->getButtonState(1) == JustPressed);
    assert(pen->isButtonDown(1));

    input_state.on_pen_up(pen_id, 13.0f, 24.0f, true, SDL_PEN_INPUT_ERASER_TIP, 16);
    assert(pen->isJustReleased());
    assert(pen->eraser);

    input_state.on_pen_proximity_out(pen_id, 17);
    assert(input_state.pen_count() == 0);
    assert(!pen->isInRange());
    assert(pen->isJustLeft());

    assert(pen->recentEvents.size() == 7);
    assert(pen->recentEvents.back().type == InputState::PenEventType::ProximityOut);

    input_state.begin_frame();
    assert(input_state.pen_by_id(pen_id) != nullptr);
    input_state.begin_frame();
    assert(input_state.pen_by_id(pen_id) == nullptr);
    assert(input_state.primary_pen_id() == 0);
}

void test_pen_ids_do_not_alias_and_primary_moves_to_remaining_pen()
{
    InputState input_state;

    constexpr SDL_PenID pen_a = static_cast<SDL_PenID>(77);
    constexpr SDL_PenID pen_b = static_cast<SDL_PenID>(88);

    input_state.on_pen_proximity_in(pen_a, 10);
    input_state.on_pen_proximity_in(pen_b, 11);

    assert(input_state.pen_count() == 2);
    assert(input_state.pen_by_id(pen_a) != nullptr);
    assert(input_state.pen_by_id(pen_b) != nullptr);
    assert(input_state.pen_by_id(pen_a) != input_state.pen_by_id(pen_b));
    assert(input_state.primary_pen_id() == pen_b);

    input_state.on_pen_proximity_out(pen_b, 12);
    assert(input_state.pen_count() == 1);
    assert(input_state.primary_pen_id() == pen_a);
}

} // namespace

int main()
{
    test_pen_lifecycle_tracks_hover_tip_buttons_axes_and_history();
    test_pen_ids_do_not_alias_and_primary_moves_to_remaining_pen();
    std::cout << "test_input_pen_state: all tests passed\n";
    return 0;
}
