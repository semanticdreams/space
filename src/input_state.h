#ifndef INPUT_STATE_H
#define INPUT_STATE_H

#include <array>
#include <cstddef>
#include <memory>
#include <optional>
#include <unordered_map>
#include <vector>

#include "input_gamepad_state.h"
#include "input_keyboard_state.h"
#include "input_mouse_state.h"

struct InputState
{
    static constexpr std::size_t PenButtonCount = 5;
    static constexpr std::size_t PenEventHistoryLimit = 128;

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

    enum class PenEventType
    {
        ProximityIn,
        ProximityOut,
        Motion,
        Down,
        Up,
        ButtonDown,
        ButtonUp,
        Axis
    };

    struct PenEventRecord
    {
        PenEventType type {PenEventType::Motion};
        SDL_PenID penId {0};
        float x {0.0F};
        float y {0.0F};
        float xrel {0.0F};
        float yrel {0.0F};
        Uint64 timestamp {0};
        SDL_PenInputFlags inputState {0};
        bool eraser {false};
        bool inRange {false};
        bool down {false};
        Uint8 button {0};
        bool buttonDown {false};
        SDL_PenAxis axis {SDL_PEN_AXIS_PRESSURE};
        float value {0.0F};
        std::array<float, SDL_PEN_AXIS_COUNT> axes {};
    };

    struct PenState
    {
        SDL_PenID penId {0};
        float x {0.0F};
        float y {0.0F};
        float xrel {0.0F};
        float yrel {0.0F};
        Uint64 updateTimestamp {0};
        SDL_PenInputFlags inputState {0};
        bool eraser {false};
        bool currentInRange {false};
        bool previousInRange {false};
        bool currentDown {false};
        bool previousDown {false};
        bool hasPosition {false};
        Uint32 seenAxesMask {0};
        std::array<bool, PenButtonCount> currentButtons {};
        std::array<bool, PenButtonCount> previousButtons {};
        std::array<float, SDL_PEN_AXIS_COUNT> axes {};
        std::vector<PenEventRecord> recentEvents;

        void begin_frame();
        void set_proximity(bool inRange, Uint64 timestamp);
        void set_motion(float x,
                        float y,
                        SDL_PenInputFlags inputState,
                        Uint64 timestamp);
        void set_touch(float x,
                       float y,
                       bool eraser,
                       bool down,
                       SDL_PenInputFlags inputState,
                       Uint64 timestamp);
        void set_button(float x,
                        float y,
                        Uint8 button,
                        bool down,
                        SDL_PenInputFlags inputState,
                        Uint64 timestamp);
        void set_axis(float x,
                      float y,
                      SDL_PenAxis axis,
                      float value,
                      SDL_PenInputFlags inputState,
                      Uint64 timestamp);
        void push_event(const PenEventRecord& record);

        [[nodiscard]] KeyStatus getProximityState() const;
        [[nodiscard]] KeyStatus getTipState() const;
        [[nodiscard]] KeyStatus getButtonState(Uint8 button) const;
        [[nodiscard]] bool isInRange() const;
        [[nodiscard]] bool isJustEntered() const;
        [[nodiscard]] bool isHovering() const;
        [[nodiscard]] bool isJustLeft() const;
        [[nodiscard]] bool isUp() const;
        [[nodiscard]] bool isFree() const;
        [[nodiscard]] bool isJustPressed() const;
        [[nodiscard]] bool isDown() const;
        [[nodiscard]] bool isHeld() const;
        [[nodiscard]] bool isJustReleased() const;
        [[nodiscard]] bool isButtonDown(Uint8 button) const;
        [[nodiscard]] bool hasAxis(SDL_PenAxis axis) const;
        [[nodiscard]] float axis(SDL_PenAxis axis) const;
    };

    KeyboardState keyboardState;
    MouseState mouseState;
    std::unordered_map<SDL_JoystickID, std::shared_ptr<GamepadState>> gamepadStates;
    std::unordered_map<TouchContactId, std::shared_ptr<TouchPointState>, TouchContactIdHash> touchPoints;
    std::unordered_map<SDL_PenID, std::shared_ptr<PenState>> penStates;
    SDL_JoystickID primaryGamepadId {0};
    std::optional<TouchContactId> primaryTouchId;
    SDL_PenID primaryPenId {0};

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
    void on_pen_proximity_in(SDL_PenID penId, Uint64 timestamp);
    void on_pen_proximity_out(SDL_PenID penId, Uint64 timestamp);
    void on_pen_motion(SDL_PenID penId,
                       float x,
                       float y,
                       SDL_PenInputFlags inputState,
                       Uint64 timestamp);
    void on_pen_down(SDL_PenID penId,
                     float x,
                     float y,
                     bool eraser,
                     SDL_PenInputFlags inputState,
                     Uint64 timestamp);
    void on_pen_up(SDL_PenID penId,
                   float x,
                   float y,
                   bool eraser,
                   SDL_PenInputFlags inputState,
                   Uint64 timestamp);
    void on_pen_button(SDL_PenID penId,
                       float x,
                       float y,
                       Uint8 button,
                       bool down,
                       SDL_PenInputFlags inputState,
                       Uint64 timestamp);
    void on_pen_axis(SDL_PenID penId,
                     float x,
                     float y,
                     SDL_PenAxis axis,
                     float value,
                     SDL_PenInputFlags inputState,
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
    [[nodiscard]] size_t pen_count() const;
    [[nodiscard]] SDL_PenID primary_pen_id() const;
    [[nodiscard]] const PenState* primary_pen() const;
    [[nodiscard]] PenState* primary_pen();
    [[nodiscard]] const PenState* pen_by_id(SDL_PenID penId) const;
    [[nodiscard]] PenState* pen_by_id(SDL_PenID penId);
    [[nodiscard]] std::vector<SDL_PenID> pen_ids() const;

private:
    std::shared_ptr<GamepadState> ensure_gamepad(SDL_JoystickID instanceId);
    std::shared_ptr<TouchPointState> ensure_touch(SDL_TouchID touchId, SDL_FingerID fingerId);
    std::shared_ptr<PenState> ensure_pen(SDL_PenID penId);
    [[nodiscard]] const TouchPointState* touch_by_id(const TouchContactId& id) const;
    [[nodiscard]] TouchPointState* touch_by_id(const TouchContactId& id);
    void assign_primary_if_missing(SDL_JoystickID preferredId);
    void assign_primary_touch_if_missing(const std::optional<TouchContactId>& preferredId);
    void assign_primary_pen_if_missing(SDL_PenID preferredId);
};

#endif
