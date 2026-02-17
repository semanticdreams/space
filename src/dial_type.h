#ifndef DIAL_TYPE_H
#define DIAL_TYPE_H

#include <array>
#include <optional>
#include <vector>

struct DialTypePendingInput
{
    std::vector<int> left {};
    std::vector<int> right {};
};

struct DialTypeStickDump
{
    float positionX {0.0F};
    float positionY {0.0F};
    float angle {0.0F};
    bool active {false};
    bool dialing {false};
};

struct DialTypeDump
{
    DialTypeStickDump left {};
    DialTypeStickDump right {};
    bool hasInput {false};
    std::optional<DialTypePendingInput> pending {};
};

class DialType
{
public:
    DialType();
    ~DialType();
    DialType(const DialType&) = delete;
    DialType& operator=(const DialType&) = delete;
    DialType(DialType&&) noexcept;
    DialType& operator=(DialType&&) noexcept;

    void reset();
    bool update(float leftX, float leftY, float rightX, float rightY);
    bool has_input() const;
    std::optional<DialTypePendingInput> poll();
    DialTypeDump dump() const;

private:
    class Stick
    {
    public:
        void reset();
        void update(float x, float y);
        [[nodiscard]] bool has_stack() const;
        [[nodiscard]] DialTypeStickDump dump() const;

        bool active {false};
        bool dialing {false};
        std::vector<int> stack {};

    private:
        struct ShapedInput
        {
            float x;
            float y;
        };

        static constexpr float kDeadzoneRadius = 0.15F;
        static constexpr float kThresholdRadius = 0.9F;
        static constexpr float kDialingThreshold = 0.8F;
        static constexpr float kPi = 3.14159265358979323846F;
        static constexpr float kTau = 6.28318530717958647692F;
        static const std::array<float, 8> kSectorAngles8;

        static ShapedInput apply_deadzone(float x, float y);
        static float norm_angle(float angle);
        static float angle_from_coordinates(float x, float y);
        static bool angle_between(float angle, float a, float b);
        static int get_sector_8(float x, float y);
        static int get_sector_4(float x, float y);
        static bool test_threshold(float x, float y);
        static float angle_diff(float a, float b);
        void reset_sector_counts();

        float positionX = 0.0F;
        float positionY = 0.0F;
        float startX = 0.0F;
        float startY = 0.0F;
        float startAngle = 0.0F;
        std::array<int, 8> sectorCounts {};
    };

    Stick left {};
    Stick right {};
    std::optional<DialTypePendingInput> pending;
};

#endif
