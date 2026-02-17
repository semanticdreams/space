#include "dial_type.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

const std::array<float, 8> DialType::Stick::kSectorAngles8 {
    4.42F,
    5.01F,
    5.99F,
    0.293F,
    1.2784F,
    1.8638F,
    2.8492F,
    3.4346F,
};

void DialType::Stick::reset()
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

void DialType::Stick::update(float x, float y)
{
    const ShapedInput shaped = apply_deadzone(x, y);
    positionX = shaped.x;
    positionY = shaped.y;

    if (test_threshold(positionX, positionY)) {
        const float angle = angle_from_coordinates(positionX, positionY);
        if (!active) {
            startX = positionX;
            startY = positionY;
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
            const int sector = get_sector_4(positionX, positionY);
            const bool can_append =
                stack.empty() ||
                (sector != stack.back() &&
                 (stack.size() < 2 || sector != stack[stack.size() - 2]));
            if (can_append) {
                stack.push_back(sector);
            }
        } else {
            const int sector = get_sector_8(positionX, positionY);
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

bool DialType::Stick::has_stack() const
{
    return !stack.empty();
}

DialTypeStickDump DialType::Stick::dump() const
{
    DialTypeStickDump out;
    out.positionX = positionX;
    out.positionY = positionY;
    out.angle = angle_from_coordinates(positionX, positionY);
    out.active = active;
    out.dialing = dialing;
    return out;
}

DialType::Stick::ShapedInput DialType::Stick::apply_deadzone(float x, float y)
{
    const float magnitude = std::sqrt(x * x + y * y);
    if (magnitude <= kDeadzoneRadius) {
        return {0.0F, 0.0F};
    }

    const float clamped = std::min(1.0F, magnitude);
    const float scaled = (clamped - kDeadzoneRadius) / (1.0F - kDeadzoneRadius);
    const float direction_x = x / magnitude;
    const float direction_y = y / magnitude;
    return {direction_x * scaled, direction_y * scaled};
}

float DialType::Stick::norm_angle(float angle)
{
    float result = std::fmod(20.0F * kPi + angle, kTau);
    if (result < 0.0F) {
        result += kTau;
    }
    return result;
}

float DialType::Stick::angle_from_coordinates(float x, float y)
{
    return norm_angle(std::atan2(y, x));
}

bool DialType::Stick::angle_between(float angle, float a, float b)
{
    if (a < b) {
        return a <= angle && angle <= b;
    }
    return a <= angle || angle <= b;
}

int DialType::Stick::get_sector_8(float x, float y)
{
    const float angle = angle_from_coordinates(x, y);
    for (int i = 0; i < 8; ++i) {
        const int a = i;
        const int b = (i + 1) % 8;
        if (angle_between(angle, kSectorAngles8[static_cast<size_t>(a)], kSectorAngles8[static_cast<size_t>(b)])) {
            return i;
        }
    }
    return 0;
}

int DialType::Stick::get_sector_4(float x, float y)
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

bool DialType::Stick::test_threshold(float x, float y)
{
    if (x == 0.0F && y == 0.0F) {
        return false;
    }
    return x * x + y * y > kThresholdRadius * kThresholdRadius;
}

float DialType::Stick::angle_diff(float a, float b)
{
    const float f = std::fmod((a - b + kTau), kTau);
    const float g = std::fmod((b - a + kTau), kTau);
    return (f < g) ? -f : g;
}

void DialType::Stick::reset_sector_counts()
{
    sectorCounts.fill(0);
}

DialType::DialType()
{
    left.reset();
    right.reset();
}

DialType::~DialType() = default;
DialType::DialType(DialType&&) noexcept = default;
DialType& DialType::operator=(DialType&&) noexcept = default;

void DialType::reset()
{
    left.reset();
    right.reset();
    pending.reset();
}

bool DialType::update(float leftX, float leftY, float rightX, float rightY)
{
    left.update(leftX, leftY);
    right.update(rightX, rightY);

    if (!left.active && !right.active && (left.has_stack() || right.has_stack())) {
        pending = DialTypePendingInput {left.stack, right.stack};
        left.reset();
        right.reset();
        return true;
    }
    return false;
}

bool DialType::has_input() const
{
    return pending.has_value();
}

std::optional<DialTypePendingInput> DialType::poll()
{
    std::optional<DialTypePendingInput> out = pending;
    pending.reset();
    return out;
}

DialTypeDump DialType::dump() const
{
    DialTypeDump out;
    out.left = left.dump();
    out.right = right.dump();
    out.hasInput = pending.has_value();
    out.pending = pending;
    return out;
}
