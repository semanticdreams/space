#ifndef INPUT_STATE_H
#define INPUT_STATE_H

#include <memory>
#include <optional>
#include <unordered_map>
#include <vector>

#include "input_gamepad_state.h"
#include "input_keyboard_state.h"
#include "input_mouse_state.h"

struct InputState
{
    struct TouchContactId
    {
        SDL_TouchID touchId {0};
        SDL_FingerID fingerId {0};

        [[nodiscard]] bool valid() const;
        [[nodiscard]] bool operator==(const TouchContactId& other) const;
    };

    struct TouchContactIdHash
    {
        [[nodiscard]] std::size_t operator()(const TouchContactId& id) const;
    };

    struct TouchPointState
    {
        SDL_TouchID touchId {0};
        SDL_FingerID fingerId {0};
        float x {0.0F};
        float y {0.0F};
        float dx {0.0F};
        float dy {0.0F};
        float pressure {0.0F};
        Uint64 updateTimestamp {0};
        bool currentDown {false};
        bool previousDown {false};

        void begin_frame();
        void set_contact(SDL_TouchID touchId,
                         SDL_FingerID fingerId,
                         float x,
                         float y,
                         float dx,
                         float dy,
                         float pressure,
                         bool pressed,
                         Uint64 timestamp);

        [[nodiscard]] KeyStatus getTouchState() const;
        [[nodiscard]] bool isUp() const;
        [[nodiscard]] bool isFree() const;
        [[nodiscard]] bool isJustPressed() const;
        [[nodiscard]] bool isDown() const;
        [[nodiscard]] bool isHeld() const;
        [[nodiscard]] bool isJustReleased() const;
    };

    KeyboardState keyboardState;
    MouseState mouseState;
    std::unordered_map<SDL_JoystickID, std::shared_ptr<GamepadState>> gamepadStates;
    std::unordered_map<TouchContactId, std::shared_ptr<TouchPointState>, TouchContactIdHash> touchPoints;
    SDL_JoystickID primaryGamepadId {0};
    std::optional<TouchContactId> primaryTouchId;

    InputState();

    void begin_frame();
    void on_gamepad_connected(Sint32 deviceIndex, SDL_JoystickID instanceId, Uint64 timestamp);
    void on_gamepad_disconnected(SDL_JoystickID instanceId, Uint64 timestamp);
    void on_gamepad_button(Uint8 button, bool pressed, SDL_JoystickID instanceId, Uint64 timestamp);
    void on_gamepad_axis(Uint8 axis, float value, SDL_JoystickID instanceId, Uint64 timestamp);
    void on_touch_down(SDL_TouchID touchId,
                       SDL_FingerID fingerId,
                       float x,
                       float y,
                       float dx,
                       float dy,
                       float pressure,
                       Uint64 timestamp);
    void on_touch_motion(SDL_TouchID touchId,
                         SDL_FingerID fingerId,
                         float x,
                         float y,
                         float dx,
                         float dy,
                         float pressure,
                         Uint64 timestamp);
    void on_touch_up(SDL_TouchID touchId,
                     SDL_FingerID fingerId,
                     float x,
                     float y,
                     float dx,
                     float dy,
                     float pressure,
                     Uint64 timestamp);

    [[nodiscard]] size_t gamepad_count() const;
    [[nodiscard]] SDL_JoystickID primary_gamepad_id() const;
    [[nodiscard]] const GamepadState* primary_gamepad() const;
    [[nodiscard]] GamepadState* primary_gamepad();
    [[nodiscard]] const GamepadState* gamepad_by_id(SDL_JoystickID instanceId) const;
    [[nodiscard]] GamepadState* gamepad_by_id(SDL_JoystickID instanceId);
    [[nodiscard]] std::vector<SDL_JoystickID> gamepad_ids() const;
    [[nodiscard]] size_t touch_count() const;
    [[nodiscard]] std::optional<TouchContactId> primary_touch_id() const;
    [[nodiscard]] const TouchPointState* primary_touch() const;
    [[nodiscard]] TouchPointState* primary_touch();
    [[nodiscard]] const TouchPointState* touch_by_id(SDL_TouchID touchId, SDL_FingerID fingerId) const;
    [[nodiscard]] TouchPointState* touch_by_id(SDL_TouchID touchId, SDL_FingerID fingerId);
    [[nodiscard]] std::vector<TouchContactId> touch_ids() const;

private:
    std::shared_ptr<GamepadState> ensure_gamepad(SDL_JoystickID instanceId);
    std::shared_ptr<TouchPointState> ensure_touch(SDL_TouchID touchId, SDL_FingerID fingerId);
    [[nodiscard]] const TouchPointState* touch_by_id(const TouchContactId& id) const;
    [[nodiscard]] TouchPointState* touch_by_id(const TouchContactId& id);
    void assign_primary_if_missing(SDL_JoystickID preferredId);
    void assign_primary_touch_if_missing(const std::optional<TouchContactId>& preferredId);
};

#endif
