#include "input_state.h"
#include "input_coordinates.h"

#include <cassert>
#include <cstdint>
#include <iostream>

namespace {

void test_touch_lifecycle_tracks_primary_and_transitions()
{
    InputState input_state;

    constexpr SDL_TouchID touch_id = static_cast<SDL_TouchID>(7);
    constexpr SDL_FingerID finger_a = static_cast<SDL_FingerID>(101);
    constexpr SDL_FingerID finger_b = static_cast<SDL_FingerID>(202);

    assert(input_state.touch_count() == 0);
    assert(!input_state.primary_touch_id().has_value());
    assert(input_state.primary_touch() == nullptr);

    input_state.on_touch_down(touch_id, finger_a, 0.1f, 0.2f, 0.0f, 0.0f, 0.5f, 10);
    assert(input_state.touch_count() == 1);
    assert(input_state.primary_touch_id().has_value());
    assert(input_state.primary_touch_id()->touchId == touch_id);
    assert(input_state.primary_touch_id()->fingerId == finger_a);
    InputState::TouchPointState* touch_a = input_state.touch_by_id(touch_id, finger_a);
    assert(touch_a != nullptr);
    assert(touch_a->touchId == touch_id);
    assert(touch_a->fingerId == finger_a);
    assert(touch_a->isJustPressed());

    input_state.begin_frame();
    assert(touch_a->isHeld());

    input_state.on_touch_motion(touch_id, finger_a, 0.4f, 0.6f, 0.3f, 0.4f, 0.8f, 11);
    assert(touch_a->isDown());
    assert(touch_a->x == 0.4f);
    assert(touch_a->y == 0.6f);
    assert(touch_a->dx == 0.3f);
    assert(touch_a->dy == 0.4f);
    assert(touch_a->pressure == 0.8f);

    input_state.on_touch_down(touch_id, finger_b, 0.7f, 0.8f, 0.0f, 0.0f, 0.9f, 12);
    assert(input_state.touch_count() == 2);
    assert(input_state.primary_touch_id()->touchId == touch_id);
    assert(input_state.primary_touch_id()->fingerId == finger_a);
    assert(input_state.touch_by_id(touch_id, finger_b) != nullptr);

    input_state.on_touch_up(touch_id, finger_a, 0.4f, 0.6f, 0.0f, 0.0f, 0.1f, 13);
    assert(input_state.touch_count() == 1);
    assert(touch_a->isJustReleased());
    assert(input_state.primary_touch_id()->touchId == touch_id);
    assert(input_state.primary_touch_id()->fingerId == finger_b);
    assert(input_state.primary_touch() == input_state.touch_by_id(touch_id, finger_b));

    input_state.begin_frame();
    assert(input_state.touch_by_id(touch_id, finger_a) != nullptr);
    input_state.begin_frame();
    assert(input_state.touch_by_id(touch_id, finger_a) == nullptr);

    input_state.on_touch_up(touch_id, finger_b, 0.7f, 0.8f, 0.0f, 0.0f, 0.0f, 14);
    assert(input_state.touch_count() == 0);
    assert(!input_state.primary_touch_id().has_value());
    input_state.begin_frame();
    input_state.begin_frame();
    assert(input_state.touch_by_id(touch_id, finger_b) == nullptr);
}

void test_touch_contacts_do_not_alias_same_finger_on_different_touch_devices()
{
    InputState input_state;

    constexpr SDL_TouchID touch_a = static_cast<SDL_TouchID>(7);
    constexpr SDL_TouchID touch_b = static_cast<SDL_TouchID>(8);
    constexpr SDL_FingerID finger_id = static_cast<SDL_FingerID>(101);

    input_state.on_touch_down(touch_a, finger_id, 0.1f, 0.2f, 0.0f, 0.0f, 0.5f, 10);
    input_state.on_touch_down(touch_b, finger_id, 0.7f, 0.8f, 0.0f, 0.0f, 0.9f, 11);

    assert(input_state.touch_count() == 2);
    assert(input_state.touch_by_id(touch_a, finger_id) != nullptr);
    assert(input_state.touch_by_id(touch_b, finger_id) != nullptr);
    assert(input_state.touch_by_id(touch_a, finger_id) != input_state.touch_by_id(touch_b, finger_id));

    const std::vector<InputState::TouchContactId> ids = input_state.touch_ids();
    assert(ids.size() == 2);

    input_state.on_touch_up(touch_a, finger_id, 0.1f, 0.2f, 0.0f, 0.0f, 0.0f, 12);
    input_state.on_touch_up(touch_b, finger_id, 0.7f, 0.8f, 0.0f, 0.0f, 0.0f, 13);
    input_state.begin_frame();
    input_state.begin_frame();
    assert(input_state.touch_by_id(touch_a, finger_id) == nullptr);
    assert(input_state.touch_by_id(touch_b, finger_id) == nullptr);
}

void test_normalized_coordinates_scale_to_window_size()
{
    const auto [x, y] = normalized_to_window_coordinates(0.25f, 0.75f, 1600, 900);
    assert(x == 400.0f);
    assert(y == 675.0f);
}

void test_negative_window_size_clamps_to_zero()
{
    const auto [x, y] = normalized_to_window_coordinates(0.5f, 0.5f, -1, -1);
    assert(x == 0.0f);
    assert(y == 0.0f);
}

} // namespace

int main()
{
    test_touch_lifecycle_tracks_primary_and_transitions();
    test_touch_contacts_do_not_alias_same_finger_on_different_touch_devices();
    test_normalized_coordinates_scale_to_window_size();
    test_negative_window_size_clamps_to_zero();
    std::cout << "test_input_touch_state: all tests passed\n";
    return 0;
}
