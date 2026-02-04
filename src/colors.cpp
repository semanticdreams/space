#include <glm/glm.hpp>
#include <glm/gtc/constants.hpp>
#include <map>
#include <algorithm>
#include <cmath>

#include "colors.h"

const glm::vec3 D65_WHITE = glm::vec3(95.047f, 100.000f, 108.883f);

// --- Gamma correction helpers ---
float gammaExpand(float c) {
    return c <= 0.04045f ? c / 12.92f : powf((c + 0.055f) / 1.055f, 2.4f);
}

float gammaCompress(float c) {
    return c <= 0.0031308f ? 12.92f * c : 1.055f * powf(c, 1.0f / 2.4f) - 0.055f;
}

// --- sRGB to XYZ ---
glm::vec3 rgbToXyz(const glm::vec3& rgb) {
    glm::vec3 linRGB = glm::vec3(
        gammaExpand(rgb.r),
        gammaExpand(rgb.g),
        gammaExpand(rgb.b)
    ) * 100.0f;

    glm::vec3 xyz;
    xyz.x = linRGB.r * 0.4124f + linRGB.g * 0.3576f + linRGB.b * 0.1805f;
    xyz.y = linRGB.r * 0.2126f + linRGB.g * 0.7152f + linRGB.b * 0.0722f;
    xyz.z = linRGB.r * 0.0193f + linRGB.g * 0.1192f + linRGB.b * 1.0570f;
    return xyz;
}

// --- XYZ to Lab ---
glm::vec3 xyzToLab(const glm::vec3& xyz) {
    auto f = [](float t) -> float {
        return t > 0.008856f ? cbrtf(t) : (7.787f * t + 16.0f / 116.0f);
    };

    glm::vec3 n = xyz / D65_WHITE;
    float fx = f(n.x);
    float fy = f(n.y);
    float fz = f(n.z);

    return glm::vec3(
        116.0f * fy - 16.0f, // L
        500.0f * (fx - fy),  // a
        200.0f * (fy - fz)   // b
    );
}

// --- Lab to XYZ ---
glm::vec3 labToXyz(const glm::vec3& lab) {
    float fy = (lab.x + 16.0f) / 116.0f;
    float fx = lab.y / 500.0f + fy;
    float fz = fy - lab.z / 200.0f;

    auto f_inv = [](float t) -> float {
        float t3 = t * t * t;
        return t3 > 0.008856f ? t3 : (t - 16.0f / 116.0f) / 7.787f;
    };

    glm::vec3 xyz;
    xyz.x = D65_WHITE.x * f_inv(fx);
    xyz.y = D65_WHITE.y * f_inv(fy);
    xyz.z = D65_WHITE.z * f_inv(fz);
    return xyz;
}

// --- XYZ to sRGB ---
glm::vec3 xyzToRgb(const glm::vec3& xyz) {
    glm::vec3 rgb;
    glm::vec3 lin = glm::vec3(
        xyz.x *  3.2406f + xyz.y * -1.5372f + xyz.z * -0.4986f,
        xyz.x * -0.9689f + xyz.y *  1.8758f + xyz.z *  0.0415f,
        xyz.x *  0.0557f + xyz.y * -0.2040f + xyz.z *  1.0570f
    ) / 100.0f;

    rgb = glm::vec3(
        gammaCompress(std::clamp(lin.r, 0.0f, 1.0f)),
        gammaCompress(std::clamp(lin.g, 0.0f, 1.0f)),
        gammaCompress(std::clamp(lin.b, 0.0f, 1.0f))
    );
    return rgb;
}

// --- RGB ↔ Lab ---
glm::vec3 rgbToLab(const glm::vec3& rgb) {
    return xyzToLab(rgbToXyz(rgb));
}

glm::vec3 labToRgb(const glm::vec3& lab) {
    return xyzToRgb(labToXyz(lab));
}

// --- Create perceptual color swatch ---
std::map<int, glm::vec3> createColorSwatch(const glm::vec3& baseColor) {
    glm::vec3 baseLab = rgbToLab(baseColor);
    std::map<int, glm::vec3> swatch;

    for (int i = 0; i < 10; ++i) {
        float delta = (i - 5) * -10.0f;  // lighter at low i, darker at high i
        float newL = std::clamp(baseLab.x + delta, 0.0f, 100.0f);

        glm::vec3 variantLab(newL, baseLab.y, baseLab.z);
        glm::vec3 variantRgb = i == 5 ? baseColor : labToRgb(variantLab);

        swatch[i * 100] = variantRgb;
    }

    return swatch;
}
