#include "input_dial_type.h"

#include <SDL3/SDL.h>

#include <cassert>
#include <cstdint>
#include <iostream>

namespace {

void feed_release_gesture(InputState& input_state, InputDialType& dial, SDL_JoystickID gamepad_id, Uint64 base_timestamp)
{
    input_state.on_gamepad_axis(SDL_GAMEPAD_AXIS_LEFTX, 1.0f, gamepad_id, base_timestamp);
    (void)dial.process_gamepad(gamepad_id);
    input_state.on_gamepad_axis(SDL_GAMEPAD_AXIS_LEFTX, 0.0f, gamepad_id, base_timestamp + 1);
    (void)dial.process_gamepad(gamepad_id);
}

void test_self_unsubscribe_during_callback()
{
    InputState input_state;
    InputDialType dial(input_state);
    constexpr SDL_JoystickID gamepad_id = 101;

    input_state.on_gamepad_connected(0, gamepad_id, 1);
    dial.activate_gamepad(gamepad_id);

    int callback_a_calls = 0;
    int callback_b_calls = 0;
    InputDialType::CallbackId callback_a_id = 0;

    callback_a_id = dial.register_callback(
        gamepad_id,
        [&](SDL_JoystickID which, const DialTypePendingInput&) {
            assert(which == gamepad_id);
            callback_a_calls += 1;
            const bool removed = dial.unregister_callback(callback_a_id);
            assert(removed);
        });
    const InputDialType::CallbackId callback_b_id = dial.register_callback(
        gamepad_id,
        [&](SDL_JoystickID which, const DialTypePendingInput&) {
            assert(which == gamepad_id);
            callback_b_calls += 1;
        });

    assert(callback_a_id != 0);
    assert(callback_b_id != 0);

    feed_release_gesture(input_state, dial, gamepad_id, 10);
    feed_release_gesture(input_state, dial, gamepad_id, 20);

    assert(callback_a_calls == 1);
    assert(callback_b_calls == 2);
    assert(!dial.unregister_callback(callback_a_id));
}

void test_register_during_dispatch_runs_next_gesture()
{
    InputState input_state;
    InputDialType dial(input_state);
    constexpr SDL_JoystickID gamepad_id = 102;

    input_state.on_gamepad_connected(0, gamepad_id, 1);
    dial.activate_gamepad(gamepad_id);

    int callback_a_calls = 0;
    int callback_b_calls = 0;
    int callback_c_calls = 0;
    InputDialType::CallbackId callback_c_id = 0;

    const InputDialType::CallbackId callback_a_id = dial.register_callback(
        gamepad_id,
        [&](SDL_JoystickID which, const DialTypePendingInput&) {
            assert(which == gamepad_id);
            callback_a_calls += 1;
            if (callback_c_id == 0) {
                callback_c_id = dial.register_callback(
                    gamepad_id,
                    [&](SDL_JoystickID inner_which, const DialTypePendingInput&) {
                        assert(inner_which == gamepad_id);
                        callback_c_calls += 1;
                    });
                assert(callback_c_id != 0);
            }
        });
    const InputDialType::CallbackId callback_b_id = dial.register_callback(
        gamepad_id,
        [&](SDL_JoystickID which, const DialTypePendingInput&) {
            assert(which == gamepad_id);
            callback_b_calls += 1;
        });

    assert(callback_a_id != 0);
    assert(callback_b_id != 0);

    feed_release_gesture(input_state, dial, gamepad_id, 30);
    assert(callback_a_calls == 1);
    assert(callback_b_calls == 1);
    assert(callback_c_calls == 0);

    feed_release_gesture(input_state, dial, gamepad_id, 40);
    assert(callback_a_calls == 2);
    assert(callback_b_calls == 2);
    assert(callback_c_calls == 1);
}

void test_deactivate_gamepad_removes_subscriptions()
{
    InputState input_state;
    InputDialType dial(input_state);
    constexpr SDL_JoystickID gamepad_id = 103;

    input_state.on_gamepad_connected(0, gamepad_id, 1);
    dial.activate_gamepad(gamepad_id);

    int callback_calls = 0;
    const InputDialType::CallbackId callback_id = dial.register_callback(
        gamepad_id,
        [&](SDL_JoystickID which, const DialTypePendingInput&) {
            assert(which == gamepad_id);
            callback_calls += 1;
        });
    assert(callback_id != 0);

    dial.deactivate_gamepad(gamepad_id);
    input_state.on_gamepad_disconnected(gamepad_id, 2);

    input_state.on_gamepad_connected(0, gamepad_id, 3);
    dial.activate_gamepad(gamepad_id);
    feed_release_gesture(input_state, dial, gamepad_id, 50);

    assert(callback_calls == 0);
    assert(!dial.unregister_callback(callback_id));
}

} // namespace

int main()
{
    test_self_unsubscribe_during_callback();
    test_register_during_dispatch_runs_next_gesture();
    test_deactivate_gamepad_removes_subscriptions();
    std::cout << "test_input_dial_type: all tests passed\n";
    return 0;
}
