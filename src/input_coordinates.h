#ifndef INPUT_COORDINATES_H
#define INPUT_COORDINATES_H

#include <algorithm>
#include <utility>

inline std::pair<float, float> normalized_to_window_coordinates(float normalized_x, float normalized_y, int width, int height)
{
    const int safe_width = std::max(width, 0);
    const int safe_height = std::max(height, 0);
    return {
        normalized_x * static_cast<float>(safe_width),
        normalized_y * static_cast<float>(safe_height),
    };
}

#endif
