#include <sol/sol.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>
#include <stdexcept>
#include <vector>

namespace {

class DialTypeStick
{
public:
    static constexpr float kThresholdRadius = 0.9F;
    static constexpr float kDialingThreshold = 0.8F;
    static constexpr float kPi = 3.14159265358979323846F;
    static constexpr float kTau = 6.28318530717958647692F;

    void reset()
    {
        positionX = 0.0F;
        positionY = 0.0F;
        startX = 0.0F;
        startY = 0.0F;
        startAngle = 0.0F;
        active = false;
        dialing = false;
        stack.clear();
        reset_sector_counts();
    }

    void update(float x, float y)
    {
        positionX = x;
        positionY = y;

        if (test_threshold(x, y)) {
            const float angle = angle_from_coordinates(x, y);
            if (!active) {
                startX = x;
                startY = y;
                startAngle = angle;
                active = true;
            }

            if (!dialing) {
                if (std::abs(angle_diff(angle, startAngle)) > kDialingThreshold) {
                    stack.push_back(get_sector_4(startX, startY));
                    dialing = true;
                }
            }

            if (dialing) {
                const int sector = get_sector_4(x, y);
                const bool can_append =
                    stack.empty() ||
                    (sector != stack.back() &&
                     (stack.size() < 2 || sector != stack[stack.size() - 2]));
                if (can_append) {
                    stack.push_back(sector);
                }
            } else {
                const int sector = get_sector_8(x, y);
                sectorCounts[static_cast<size_t>(sector)] += 1;
            }
            return;
        }

        if (!active) {
            return;
        }

        active = false;
        if (!dialing) {
            int max_sector = 0;
            int max_count = 0;
            for (int i = 0; i < 8; ++i) {
                const int count = sectorCounts[static_cast<size_t>(i)];
                if (count > max_count) {
                    max_count = count;
                    max_sector = i;
                }
            }
            if (max_count > 0) {
                stack.push_back(max_sector);
            }
        } else {
            dialing = false;
        }
        reset_sector_counts();
    }

    [[nodiscard]] bool has_stack() const
    {
        return !stack.empty();
    }

    [[nodiscard]] sol::table dump(sol::this_state state) const
    {
        sol::state_view lua(state);
        sol::table out = lua.create_table();
        sol::table position = lua.create_table();
        position[1] = positionX;
        position[2] = positionY;
        out["position"] = position;
        out["angle"] = angle_from_coordinates(positionX, positionY);
        out["active"] = active;
        out["dialing"] = dialing;
        return out;
    }

    bool active = false;
    bool dialing = false;
    std::vector<int> stack {};

private:
    static float norm_angle(float angle)
    {
        float result = std::fmod(20.0F * kPi + angle, kTau);
        if (result < 0.0F) {
            result += kTau;
        }
        return result;
    }

    static float angle_from_coordinates(float x, float y)
    {
        return norm_angle(std::atan2(y, x));
    }

    static bool angle_between(float angle, float a, float b)
    {
        if (a < b) {
            return a <= angle && angle <= b;
        }
        return a <= angle || angle <= b;
    }

    static std::array<float, 8> sector_angles_8()
    {
        std::array<float, 8> angles {4.32F, 5.11F, 5.89F, 0.393F, 1.1784F, 1.9638F, 2.7492F, 3.5346F};
        constexpr float narrowing_shift = 0.1F;
        angles[0] += narrowing_shift;
        angles[1] -= narrowing_shift;
        angles[2] += narrowing_shift;
        angles[3] -= narrowing_shift;
        angles[4] += narrowing_shift;
        angles[5] -= narrowing_shift;
        angles[6] += narrowing_shift;
        angles[7] -= narrowing_shift;
        return angles;
    }

    static int get_sector_8(float x, float y)
    {
        const auto sector_angles = sector_angles_8();
        const float angle = angle_from_coordinates(x, y);
        for (int i = 0; i < 8; ++i) {
            const int a = i;
            const int b = (i + 1) % 8;
            if (angle_between(angle, sector_angles[static_cast<size_t>(a)], sector_angles[static_cast<size_t>(b)])) {
                return i;
            }
        }
        return 0;
    }

    static int get_sector_4(float x, float y)
    {
        const float y_inv = -y;
        if (y_inv >= std::abs(x)) {
            return 0;
        }
        if (-y_inv >= std::abs(x)) {
            return 2;
        }
        if (x >= std::abs(y_inv)) {
            return 1;
        }
        if (-x >= std::abs(y_inv)) {
            return 3;
        }
        throw std::runtime_error("failed to compute sector4");
    }

    static bool test_threshold(float x, float y)
    {
        if (x == 0.0F && y == 0.0F) {
            return false;
        }
        return x * x + y * y > kThresholdRadius * kThresholdRadius;
    }

    static float angle_diff(float a, float b)
    {
        const float f = std::fmod((a - b + kTau), kTau);
        const float g = std::fmod((b - a + kTau), kTau);
        return (f < g) ? -f : g;
    }

    void reset_sector_counts()
    {
        sectorCounts.fill(0);
    }

    float positionX = 0.0F;
    float positionY = 0.0F;
    float startX = 0.0F;
    float startY = 0.0F;
    float startAngle = 0.0F;
    std::array<int, 8> sectorCounts {};
};

class DialType
{
public:
    DialType()
    {
        left.reset();
        right.reset();
    }

    void reset()
    {
        left.reset();
        right.reset();
        pending.reset();
    }

    bool update(float leftX, float leftY, float rightX, float rightY)
    {
        left.update(leftX, leftY);
        right.update(rightX, rightY);

        if (!left.active && !right.active && (left.has_stack() || right.has_stack())) {
            pending = PendingInput {left.stack, right.stack};
            left.reset();
            right.reset();
            return true;
        }
        return false;
    }

    sol::object poll(sol::this_state state)
    {
        sol::state_view lua(state);
        if (!pending.has_value()) {
            return sol::make_object(lua, sol::nil);
        }

        sol::table out = lua.create_table();
        out[1] = to_lua_array(lua, pending->left);
        out[2] = to_lua_array(lua, pending->right);
        pending.reset();
        return sol::make_object(lua, out);
    }

    bool has_input() const
    {
        return pending.has_value();
    }

    sol::table dump(sol::this_state state) const
    {
        sol::state_view lua(state);
        sol::table out = lua.create_table();
        sol::table sticks = lua.create_table();
        sticks[1] = left.dump(state);
        sticks[2] = right.dump(state);
        out["sticks"] = sticks;
        out["has-input"] = pending.has_value();
        if (pending.has_value()) {
            out["pending"] = to_lua_pair(lua, pending.value());
        }
        return out;
    }

private:
    struct PendingInput
    {
        std::vector<int> left {};
        std::vector<int> right {};
    };

    static sol::table to_lua_array(sol::state_view lua, const std::vector<int>& values)
    {
        sol::table out = lua.create_table();
        for (size_t i = 0; i < values.size(); ++i) {
            out[static_cast<int>(i + 1)] = values[i];
        }
        return out;
    }

    static sol::table to_lua_pair(sol::state_view lua, const PendingInput& value)
    {
        sol::table out = lua.create_table();
        out[1] = to_lua_array(lua, value.left);
        out[2] = to_lua_array(lua, value.right);
        return out;
    }

    DialTypeStick left {};
    DialTypeStick right {};
    std::optional<PendingInput> pending {};
};

sol::table create_dial_type_table(sol::state_view lua)
{
    sol::table dial_type_table = lua.create_table();
    dial_type_table.new_usertype<DialType>(
        "DialType",
        sol::constructors<DialType()>(),
        "update", &DialType::update,
        "poll", &DialType::poll,
        "has-input", &DialType::has_input,
        "dump", &DialType::dump,
        "reset", &DialType::reset);

    dial_type_table.set_function("DialType", []() {
        return DialType();
    });

    return dial_type_table;
}

} // namespace

void lua_bind_dial_type(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("dial-type", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_dial_type_table(lua);
    });
}
