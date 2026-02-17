#ifndef INPUT_DIAL_TYPE_H
#define INPUT_DIAL_TYPE_H

#include <functional>
#include <optional>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "dial_type.h"
#include "input_state.h"

class InputDialType
{
public:
    using CallbackId = uint64_t;
    using CallbackFn = std::function<void(SDL_JoystickID, const DialTypePendingInput&)>;

    explicit InputDialType(InputState& inputState);

    void reset();
    bool update();
    bool update_primary();
    bool update_controller(SDL_JoystickID instanceId);

    [[nodiscard]] bool has_input() const;
    [[nodiscard]] bool has_input_for(SDL_JoystickID instanceId) const;
    std::optional<DialTypePendingInput> poll_primary();
    std::optional<DialTypePendingInput> poll_controller(SDL_JoystickID instanceId);
    [[nodiscard]] std::vector<SDL_JoystickID> controller_ids() const;
    void activate_controller(SDL_JoystickID instanceId);
    void deactivate_controller(SDL_JoystickID instanceId);
    [[nodiscard]] bool is_controller_active(SDL_JoystickID instanceId) const;
    [[nodiscard]] bool process_controller(SDL_JoystickID instanceId);
    CallbackId register_callback(SDL_JoystickID instanceId, CallbackFn callback);
    bool unregister_callback(CallbackId callbackId);

private:
    struct Subscription
    {
        SDL_JoystickID instanceId {-1};
        CallbackFn callback {};
    };

    void dispatch(SDL_JoystickID instanceId, const DialTypePendingInput& input);
    void remove_controller_subscriptions(SDL_JoystickID instanceId);

    InputState* inputState;
    std::unordered_map<SDL_JoystickID, DialType> dialByController;
    std::unordered_set<SDL_JoystickID> activeControllers;
    std::unordered_map<CallbackId, Subscription> subscriptions;
    std::unordered_map<SDL_JoystickID, std::unordered_set<CallbackId>> subscriptionIdsByController;
    CallbackId nextCallbackId {1};
};

#endif
