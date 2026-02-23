#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include <glm/glm.hpp>
#include <glm/gtc/constants.hpp>
#include <glm/gtc/matrix_inverse.hpp>

#include "colors.h"

namespace {

constexpr float CIE_E = 216.0f / 24389.0f;
constexpr float CIE_K = 24389.0f / 27.0f;

std::string to_lower(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

glm::mat3 make_mat3_rows(float r0c0, float r0c1, float r0c2,
                         float r1c0, float r1c1, float r1c2,
                         float r2c0, float r2c1, float r2c2)
{
    glm::mat3 matrix(1.0f);
    matrix[0][0] = r0c0;
    matrix[1][0] = r0c1;
    matrix[2][0] = r0c2;
    matrix[0][1] = r1c0;
    matrix[1][1] = r1c1;
    matrix[2][1] = r1c2;
    matrix[0][2] = r2c0;
    matrix[1][2] = r2c1;
    matrix[2][2] = r2c2;
    return matrix;
}

float gamma_expand(float c)
{
    return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

float gamma_compress(float c)
{
    return c <= 0.0031308f ? 12.92f * c : 1.055f * std::pow(c, 1.0f / 2.4f) - 0.055f;
}

float normalize_hue(float hue)
{
    float normalized = std::fmod(hue, 360.0f);
    if (normalized < 0.0f) {
        normalized += 360.0f;
    }
    return normalized;
}

float rgb_to_hue(float r, float g, float b, float v_min, float v_max)
{
    if (v_max == v_min) {
        return 0.0f;
    }
    if (v_max == r) {
        return std::fmod(60.0f * ((g - b) / (v_max - v_min)) + 360.0f, 360.0f);
    }
    if (v_max == g) {
        return 60.0f * ((b - r) / (v_max - v_min)) + 120.0f;
    }
    return 60.0f * ((r - g) / (v_max - v_min)) + 240.0f;
}

float hsl_component(float q, float p, float c)
{
    if (c < 0.0f) {
        c += 1.0f;
    }
    if (c > 1.0f) {
        c -= 1.0f;
    }
    if (c < 1.0f / 6.0f) {
        return p + ((q - p) * 6.0f * c);
    }
    if (c < 0.5f) {
        return q;
    }
    if (c < 2.0f / 3.0f) {
        return p + ((q - p) * 6.0f * ((2.0f / 3.0f) - c));
    }
    return p;
}

float f_xyz_to_lab(float t)
{
    return t > CIE_E ? std::cbrt(t) : (7.787f * t + 16.0f / 116.0f);
}

float f_lab_to_xyz(float t)
{
    float t3 = t * t * t;
    return t3 > CIE_E ? t3 : (t - 16.0f / 116.0f) / 7.787f;
}

float safe_div(float numerator, float denominator)
{
    return std::abs(denominator) < 1e-12f ? 0.0f : numerator / denominator;
}

const glm::vec3 D65_WHITE_2DEG = glm::vec3(95.047f, 100.0f, 108.883f);

const std::unordered_map<std::string, std::unordered_map<std::string, glm::vec3>> ILLUMINANTS = {
    {"2",
     {{"a", glm::vec3(109.850f, 100.000f, 35.585f)},
      {"b", glm::vec3(99.072f, 100.000f, 85.223f)},
      {"c", glm::vec3(98.074f, 100.000f, 118.232f)},
      {"d50", glm::vec3(96.422f, 100.000f, 82.521f)},
      {"d55", glm::vec3(95.682f, 100.000f, 92.149f)},
      {"d65", glm::vec3(95.047f, 100.000f, 108.883f)},
      {"d75", glm::vec3(94.972f, 100.000f, 122.638f)},
      {"e", glm::vec3(100.000f, 100.000f, 100.000f)},
      {"f2", glm::vec3(99.186f, 100.000f, 67.393f)},
      {"f7", glm::vec3(95.041f, 100.000f, 108.747f)},
      {"f11", glm::vec3(100.962f, 100.000f, 64.350f)}}},
    {"10",
     {{"d50", glm::vec3(96.720f, 100.000f, 81.430f)},
      {"d55", glm::vec3(95.800f, 100.000f, 90.930f)},
      {"d65", glm::vec3(94.810f, 100.000f, 107.300f)},
      {"d75", glm::vec3(94.416f, 100.000f, 120.640f)}}},
};

const glm::mat3 BRADFORD = make_mat3_rows(
    0.8951f, 0.2664f, -0.1614f,
    -0.7502f, 1.7135f, 0.0367f,
    0.0389f, -0.0685f, 1.0296f);

const glm::mat3 VON_KRIES = make_mat3_rows(
    0.40024f, 0.70760f, -0.08081f,
    -0.22630f, 1.16532f, 0.04570f,
    0.00000f, 0.00000f, 0.91822f);

const glm::mat3 XYZ_SCALING = make_mat3_rows(
    1.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 1.0f);

const glm::mat3 XYZ_TO_LMS_IPT = make_mat3_rows(
    0.4002f, 0.7075f, -0.0807f,
    -0.2280f, 1.1500f, 0.0612f,
    0.0000f, 0.0000f, 0.9184f);

const glm::mat3 LMS_TO_IPT = make_mat3_rows(
    0.4000f, 0.4000f, 0.2000f,
    4.4550f, -4.8510f, 0.3960f,
    0.8056f, 0.3572f, -1.1628f);

const glm::mat3 IPT_TO_LMS = glm::inverse(LMS_TO_IPT);
const glm::mat3 LMS_TO_XYZ_IPT = glm::inverse(XYZ_TO_LMS_IPT);

glm::mat3 adaptation_matrix(const std::string& adaptation)
{
    const std::string key = to_lower(adaptation);
    if (key == "bradford") {
        return BRADFORD;
    }
    if (key == "von_kries") {
        return VON_KRIES;
    }
    if (key == "xyz_scaling") {
        return XYZ_SCALING;
    }
    throw std::invalid_argument("unknown chromatic adaptation: " + adaptation);
}

} // namespace

glm::vec3 getIlluminant(const std::string& observer, const std::string& illuminant)
{
    const std::string observer_key = to_lower(observer);
    const auto observer_it = ILLUMINANTS.find(observer_key);
    if (observer_it == ILLUMINANTS.end()) {
        throw std::invalid_argument("unknown observer: " + observer);
    }

    const std::string illuminant_key = to_lower(illuminant);
    const auto illuminant_it = observer_it->second.find(illuminant_key);
    if (illuminant_it == observer_it->second.end()) {
        throw std::invalid_argument("unknown illuminant for observer " + observer + ": " + illuminant);
    }

    return illuminant_it->second;
}

glm::vec3 rgbToXyz(const glm::vec3& rgb)
{
    glm::vec3 linear = glm::vec3(
        gamma_expand(rgb.r),
        gamma_expand(rgb.g),
        gamma_expand(rgb.b)) * 100.0f;

    return glm::vec3(
        linear.r * 0.4124f + linear.g * 0.3576f + linear.b * 0.1805f,
        linear.r * 0.2126f + linear.g * 0.7152f + linear.b * 0.0722f,
        linear.r * 0.0193f + linear.g * 0.1192f + linear.b * 0.9505f);
}

glm::vec3 xyzToRgb(const glm::vec3& xyz)
{
    glm::vec3 linear = glm::vec3(
        xyz.x * 3.2406f + xyz.y * -1.5372f + xyz.z * -0.4986f,
        xyz.x * -0.9689f + xyz.y * 1.8758f + xyz.z * 0.0415f,
        xyz.x * 0.0557f + xyz.y * -0.2040f + xyz.z * 1.0570f) / 100.0f;

    return glm::vec3(
        gamma_compress(std::clamp(linear.r, 0.0f, 1.0f)),
        gamma_compress(std::clamp(linear.g, 0.0f, 1.0f)),
        gamma_compress(std::clamp(linear.b, 0.0f, 1.0f)));
}

glm::vec3 xyzToLab(const glm::vec3& xyz)
{
    return xyzToLab(xyz, "2", "d65");
}

glm::vec3 xyzToLab(const glm::vec3& xyz, const std::string& observer, const std::string& illuminant)
{
    glm::vec3 white = getIlluminant(observer, illuminant);
    glm::vec3 n = xyz / white;
    float fx = f_xyz_to_lab(n.x);
    float fy = f_xyz_to_lab(n.y);
    float fz = f_xyz_to_lab(n.z);

    return glm::vec3(
        116.0f * fy - 16.0f,
        500.0f * (fx - fy),
        200.0f * (fy - fz));
}

glm::vec3 labToXyz(const glm::vec3& lab)
{
    return labToXyz(lab, "2", "d65");
}

glm::vec3 labToXyz(const glm::vec3& lab, const std::string& observer, const std::string& illuminant)
{
    glm::vec3 white = getIlluminant(observer, illuminant);
    float fy = (lab.x + 16.0f) / 116.0f;
    float fx = lab.y / 500.0f + fy;
    float fz = fy - lab.z / 200.0f;

    return glm::vec3(
        white.x * f_lab_to_xyz(fx),
        white.y * f_lab_to_xyz(fy),
        white.z * f_lab_to_xyz(fz));
}

glm::vec3 rgbToLab(const glm::vec3& rgb)
{
    return xyzToLab(rgbToXyz(rgb));
}

glm::vec3 labToRgb(const glm::vec3& lab)
{
    return xyzToRgb(labToXyz(lab));
}

glm::vec3 labToLchab(const glm::vec3& lab)
{
    const float c = std::sqrt(lab.y * lab.y + lab.z * lab.z);
    const float h = normalize_hue(glm::degrees(std::atan2(lab.z, lab.y)));
    return glm::vec3(lab.x, c, h);
}

glm::vec3 lchabToLab(const glm::vec3& lchab)
{
    const float h_rad = glm::radians(lchab.z);
    return glm::vec3(
        lchab.x,
        std::cos(h_rad) * lchab.y,
        std::sin(h_rad) * lchab.y);
}

glm::vec3 xyzToLuv(const glm::vec3& xyz)
{
    return xyzToLuv(xyz, "2", "d65");
}

glm::vec3 xyzToLuv(const glm::vec3& xyz, const std::string& observer, const std::string& illuminant)
{
    const glm::vec3 white = getIlluminant(observer, illuminant);
    const float denom = xyz.x + 15.0f * xyz.y + 3.0f * xyz.z;
    const float u_prime = safe_div(4.0f * xyz.x, denom);
    const float v_prime = safe_div(9.0f * xyz.y, denom);

    float y_norm = xyz.y / white.y;
    if (y_norm > CIE_E) {
        y_norm = std::cbrt(y_norm);
    } else {
        y_norm = 7.787f * y_norm + 16.0f / 116.0f;
    }

    const float ref_denom = white.x + 15.0f * white.y + 3.0f * white.z;
    const float ref_u = (4.0f * white.x) / ref_denom;
    const float ref_v = (9.0f * white.y) / ref_denom;

    const float l = 116.0f * y_norm - 16.0f;
    const float u = 13.0f * l * (u_prime - ref_u);
    const float v = 13.0f * l * (v_prime - ref_v);
    return glm::vec3(l, u, v);
}

glm::vec3 luvToXyz(const glm::vec3& luv)
{
    return luvToXyz(luv, "2", "d65");
}

glm::vec3 luvToXyz(const glm::vec3& luv, const std::string& observer, const std::string& illuminant)
{
    if (luv.x <= 0.0f) {
        return glm::vec3(0.0f);
    }

    const glm::vec3 white = getIlluminant(observer, illuminant);
    const float k_times_e = CIE_K * CIE_E;
    const float ref_denom = white.x + 15.0f * white.y + 3.0f * white.z;
    const float u0 = (4.0f * white.x) / ref_denom;
    const float v0 = (9.0f * white.y) / ref_denom;

    const float var_u = luv.y / (13.0f * luv.x) + u0;
    const float var_v = luv.z / (13.0f * luv.x) + v0;

    float y = luv.x > k_times_e ? std::pow((luv.x + 16.0f) / 116.0f, 3.0f) : luv.x / CIE_K;
    y *= white.y;

    const float x = y * 9.0f * var_u / (4.0f * var_v);
    const float z = y * (12.0f - 3.0f * var_u - 20.0f * var_v) / (4.0f * var_v);
    return glm::vec3(x, y, z);
}

glm::vec3 luvToLchuv(const glm::vec3& luv)
{
    const float c = std::sqrt(luv.y * luv.y + luv.z * luv.z);
    const float h = normalize_hue(glm::degrees(std::atan2(luv.z, luv.y)));
    return glm::vec3(luv.x, c, h);
}

glm::vec3 lchuvToLuv(const glm::vec3& lchuv)
{
    const float h_rad = glm::radians(lchuv.z);
    return glm::vec3(
        lchuv.x,
        std::cos(h_rad) * lchuv.y,
        std::sin(h_rad) * lchuv.y);
}

glm::vec3 xyzToXyy(const glm::vec3& xyz)
{
    const float sum = xyz.x + xyz.y + xyz.z;
    if (sum == 0.0f) {
        return glm::vec3(0.0f);
    }
    return glm::vec3(xyz.x / sum, xyz.y / sum, xyz.y);
}

glm::vec3 xyyToXyz(const glm::vec3& xyy)
{
    if (xyy.y == 0.0f) {
        return glm::vec3(0.0f);
    }
    return glm::vec3(
        (xyy.x * xyy.z) / xyy.y,
        xyy.z,
        ((1.0f - xyy.x - xyy.y) * xyy.z) / xyy.y);
}

glm::vec3 rgbToHsv(const glm::vec3& rgb)
{
    const float v_max = std::max({rgb.r, rgb.g, rgb.b});
    const float v_min = std::min({rgb.r, rgb.g, rgb.b});
    const float h = rgb_to_hue(rgb.r, rgb.g, rgb.b, v_min, v_max);
    const float s = v_max == 0.0f ? 0.0f : 1.0f - (v_min / v_max);
    return glm::vec3(h, s, v_max);
}

glm::vec3 hsvToRgb(const glm::vec3& hsv)
{
    const float h = normalize_hue(hsv.x);
    const float s = std::clamp(hsv.y, 0.0f, 1.0f);
    const float v = std::clamp(hsv.z, 0.0f, 1.0f);

    const int h_sector = static_cast<int>(std::floor(h / 60.0f)) % 6;
    const float f = (h / 60.0f) - std::floor(h / 60.0f);
    const float p = v * (1.0f - s);
    const float q = v * (1.0f - f * s);
    const float t = v * (1.0f - (1.0f - f) * s);

    switch (h_sector) {
        case 0: return glm::vec3(v, t, p);
        case 1: return glm::vec3(q, v, p);
        case 2: return glm::vec3(p, v, t);
        case 3: return glm::vec3(p, q, v);
        case 4: return glm::vec3(t, p, v);
        case 5: return glm::vec3(v, p, q);
        default: return glm::vec3(v, t, p);
    }
}

glm::vec3 rgbToHsl(const glm::vec3& rgb)
{
    const float v_max = std::max({rgb.r, rgb.g, rgb.b});
    const float v_min = std::min({rgb.r, rgb.g, rgb.b});
    const float h = rgb_to_hue(rgb.r, rgb.g, rgb.b, v_min, v_max);
    const float l = 0.5f * (v_max + v_min);

    float s = 0.0f;
    if (v_max != v_min) {
        if (l <= 0.5f) {
            s = (v_max - v_min) / (2.0f * l);
        } else {
            s = (v_max - v_min) / (2.0f - 2.0f * l);
        }
    }

    return glm::vec3(h, s, l);
}

glm::vec3 hslToRgb(const glm::vec3& hsl)
{
    const float h = normalize_hue(hsl.x) / 360.0f;
    const float s = std::clamp(hsl.y, 0.0f, 1.0f);
    const float l = std::clamp(hsl.z, 0.0f, 1.0f);

    if (s == 0.0f) {
        return glm::vec3(l, l, l);
    }

    const float q = l < 0.5f ? l * (1.0f + s) : l + s - l * s;
    const float p = 2.0f * l - q;

    return glm::vec3(
        hsl_component(q, p, h + 1.0f / 3.0f),
        hsl_component(q, p, h),
        hsl_component(q, p, h - 1.0f / 3.0f));
}

glm::vec3 rgbToCmy(const glm::vec3& rgb)
{
    return glm::vec3(1.0f - rgb.r, 1.0f - rgb.g, 1.0f - rgb.b);
}

glm::vec3 cmyToRgb(const glm::vec3& cmy)
{
    return glm::vec3(1.0f - cmy.r, 1.0f - cmy.g, 1.0f - cmy.b);
}

glm::vec4 cmyToCmyk(const glm::vec3& cmy)
{
    const float k = std::min({cmy.r, cmy.g, cmy.b});
    if (k == 1.0f) {
        return glm::vec4(0.0f, 0.0f, 0.0f, 1.0f);
    }

    return glm::vec4(
        (cmy.r - k) / (1.0f - k),
        (cmy.g - k) / (1.0f - k),
        (cmy.b - k) / (1.0f - k),
        k);
}

glm::vec3 cmykToCmy(const glm::vec4& cmyk)
{
    return glm::vec3(
        cmyk.x * (1.0f - cmyk.w) + cmyk.w,
        cmyk.y * (1.0f - cmyk.w) + cmyk.w,
        cmyk.z * (1.0f - cmyk.w) + cmyk.w);
}

glm::vec3 xyzToIpt(const glm::vec3& xyz)
{
    const glm::vec3 lms = XYZ_TO_LMS_IPT * (xyz / 100.0f);
    glm::vec3 lms_prime;
    lms_prime.x = std::copysign(std::pow(std::abs(lms.x), 0.43f), lms.x);
    lms_prime.y = std::copysign(std::pow(std::abs(lms.y), 0.43f), lms.y);
    lms_prime.z = std::copysign(std::pow(std::abs(lms.z), 0.43f), lms.z);
    return LMS_TO_IPT * lms_prime;
}

glm::vec3 iptToXyz(const glm::vec3& ipt)
{
    const glm::vec3 lms = IPT_TO_LMS * ipt;
    glm::vec3 lms_prime;
    lms_prime.x = std::copysign(std::pow(std::abs(lms.x), 1.0f / 0.43f), lms.x);
    lms_prime.y = std::copysign(std::pow(std::abs(lms.y), 1.0f / 0.43f), lms.y);
    lms_prime.z = std::copysign(std::pow(std::abs(lms.z), 1.0f / 0.43f), lms.z);
    return (LMS_TO_XYZ_IPT * lms_prime) * 100.0f;
}

glm::vec3 adaptXyz(const glm::vec3& xyz,
                   const std::string& sourceIlluminant,
                   const std::string& targetIlluminant,
                   const std::string& observer,
                   const std::string& adaptation)
{
    const glm::vec3 wp_src = getIlluminant(observer, sourceIlluminant);
    const glm::vec3 wp_dst = getIlluminant(observer, targetIlluminant);
    const glm::mat3 m_sharp = adaptation_matrix(adaptation);

    const glm::vec3 rgb_src = m_sharp * wp_src;
    const glm::vec3 rgb_dst = m_sharp * wp_dst;

    glm::mat3 m_rat(1.0f);
    m_rat[0][0] = rgb_dst.x / rgb_src.x;
    m_rat[1][1] = rgb_dst.y / rgb_src.y;
    m_rat[2][2] = rgb_dst.z / rgb_src.z;

    const glm::mat3 m_xfm = glm::inverse(m_sharp) * m_rat * m_sharp;
    return m_xfm * xyz;
}

float deltaECie1976(const glm::vec3& lab1, const glm::vec3& lab2)
{
    return glm::length(lab1 - lab2);
}

float deltaECie1994(const glm::vec3& lab1, const glm::vec3& lab2,
                    float K_L, float K_C, float K_H, float K_1, float K_2)
{
    const float C1 = std::sqrt(lab1.y * lab1.y + lab1.z * lab1.z);
    const float C2 = std::sqrt(lab2.y * lab2.y + lab2.z * lab2.z);

    const float delta_L = lab1.x - lab2.x;
    const float delta_C = C1 - C2;

    const glm::vec3 delta_lab = lab1 - lab2;
    const float delta_H_sq = std::max(0.0f, delta_lab.y * delta_lab.y + delta_lab.z * delta_lab.z - delta_C * delta_C);
    const float delta_H = std::sqrt(delta_H_sq);

    const float S_L = 1.0f;
    const float S_C = 1.0f + K_1 * C1;
    const float S_H = 1.0f + K_2 * C1;

    const float v_L = delta_L / (K_L * S_L);
    const float v_C = delta_C / (K_C * S_C);
    const float v_H = delta_H / (K_H * S_H);
    return std::sqrt(v_L * v_L + v_C * v_C + v_H * v_H);
}

float deltaECie2000(const glm::vec3& lab1, const glm::vec3& lab2, float K_l, float K_c, float K_h)
{
    const float L1 = lab1.x;
    const float a1 = lab1.y;
    const float b1 = lab1.z;
    const float L2 = lab2.x;
    const float a2 = lab2.y;
    const float b2 = lab2.z;

    const float C1 = std::sqrt(a1 * a1 + b1 * b1);
    const float C2 = std::sqrt(a2 * a2 + b2 * b2);
    const float C_bar = 0.5f * (C1 + C2);

    const float G = 0.5f * (1.0f - std::sqrt(std::pow(C_bar, 7.0f) / (std::pow(C_bar, 7.0f) + std::pow(25.0f, 7.0f))));
    const float a1p = (1.0f + G) * a1;
    const float a2p = (1.0f + G) * a2;

    const float C1p = std::sqrt(a1p * a1p + b1 * b1);
    const float C2p = std::sqrt(a2p * a2p + b2 * b2);
    const float C_bar_p = 0.5f * (C1p + C2p);

    float h1p = glm::degrees(std::atan2(b1, a1p));
    float h2p = glm::degrees(std::atan2(b2, a2p));
    h1p = h1p < 0.0f ? h1p + 360.0f : h1p;
    h2p = h2p < 0.0f ? h2p + 360.0f : h2p;

    const float delta_Lp = L2 - L1;
    const float delta_Cp = C2p - C1p;

    float delta_hp = h2p - h1p;
    if (std::abs(delta_hp) > 180.0f) {
        delta_hp += delta_hp > 0.0f ? -360.0f : 360.0f;
    }
    const float delta_Hp = 2.0f * std::sqrt(C1p * C2p) * std::sin(glm::radians(delta_hp / 2.0f));

    const float L_bar_p = 0.5f * (L1 + L2);
    float h_bar_p = (h1p + h2p) * 0.5f;
    if (std::abs(h1p - h2p) > 180.0f) {
        h_bar_p += 180.0f;
    }
    h_bar_p = normalize_hue(h_bar_p);

    const float T = 1.0f
                    - 0.17f * std::cos(glm::radians(h_bar_p - 30.0f))
                    + 0.24f * std::cos(glm::radians(2.0f * h_bar_p))
                    + 0.32f * std::cos(glm::radians(3.0f * h_bar_p + 6.0f))
                    - 0.20f * std::cos(glm::radians(4.0f * h_bar_p - 63.0f));

    const float S_L = 1.0f + (0.015f * std::pow(L_bar_p - 50.0f, 2.0f)) /
                                 std::sqrt(20.0f + std::pow(L_bar_p - 50.0f, 2.0f));
    const float S_C = 1.0f + 0.045f * C_bar_p;
    const float S_H = 1.0f + 0.015f * C_bar_p * T;

    const float delta_ro = 30.0f * std::exp(-std::pow((h_bar_p - 275.0f) / 25.0f, 2.0f));
    const float R_C = std::sqrt(std::pow(C_bar_p, 7.0f) / (std::pow(C_bar_p, 7.0f) + std::pow(25.0f, 7.0f)));
    const float R_T = -2.0f * R_C * std::sin(2.0f * glm::radians(delta_ro));

    const float term_L = delta_Lp / (K_l * S_L);
    const float term_C = delta_Cp / (K_c * S_C);
    const float term_H = delta_Hp / (K_h * S_H);

    return std::sqrt(term_L * term_L + term_C * term_C + term_H * term_H + R_T * term_C * term_H);
}

float deltaECmc(const glm::vec3& lab1, const glm::vec3& lab2, float p_l, float p_c)
{
    const float L = lab1.x;
    const float a = lab1.y;
    const float b = lab1.z;

    const float C1 = std::sqrt(a * a + b * b);
    const float C2 = std::sqrt(lab2.y * lab2.y + lab2.z * lab2.z);

    const float delta_L = lab1.x - lab2.x;
    const float delta_C = C1 - C2;

    const glm::vec3 delta_lab = lab1 - lab2;
    const float delta_H_sq = std::max(0.0f, delta_lab.y * delta_lab.y + delta_lab.z * delta_lab.z - delta_C * delta_C);
    const float delta_H = std::sqrt(delta_H_sq);

    float H1 = glm::degrees(std::atan2(b, a));
    if (H1 < 0.0f) {
        H1 += 360.0f;
    }

    const float F = std::sqrt(std::pow(C1, 4.0f) / (std::pow(C1, 4.0f) + 1900.0f));

    float T = 0.0f;
    if (H1 >= 164.0f && H1 <= 345.0f) {
        T = 0.56f + std::abs(0.2f * std::cos(glm::radians(H1 + 168.0f)));
    } else {
        T = 0.36f + std::abs(0.4f * std::cos(glm::radians(H1 + 35.0f)));
    }

    const float S_L = L < 16.0f ? 0.511f : (0.040975f * L) / (1.0f + 0.01765f * L);
    const float S_C = ((0.0638f * C1) / (1.0f + 0.0131f * C1)) + 0.638f;
    const float S_H = S_C * (F * T + 1.0f - F);

    const float term_L = delta_L / (p_l * S_L);
    const float term_C = delta_C / (p_c * S_C);
    const float term_H = delta_H / S_H;
    return std::sqrt(term_L * term_L + term_C * term_C + term_H * term_H);
}

std::map<int, glm::vec3> createColorSwatch(const glm::vec3& baseColor)
{
    glm::vec3 baseLab = rgbToLab(baseColor);
    std::map<int, glm::vec3> swatch;

    for (int i = 0; i < 10; ++i) {
        float delta = static_cast<float>(i - 5) * -10.0f;
        float newL = std::clamp(baseLab.x + delta, 0.0f, 100.0f);

        glm::vec3 variantLab(newL, baseLab.y, baseLab.z);
        glm::vec3 variantRgb = i == 5 ? baseColor : labToRgb(variantLab);

        swatch[i * 100] = variantRgb;
    }

    return swatch;
}

std::vector<float> deltaECie1976Matrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs)
{
    std::vector<float> out;
    out.reserve(labs.size());
    for (const glm::vec3& candidate : labs) {
        out.push_back(deltaECie1976(lab, candidate));
    }
    return out;
}

std::vector<float> deltaECie1994Matrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs, float K_L, float K_C,
                                       float K_H, float K_1, float K_2)
{
    std::vector<float> out;
    out.reserve(labs.size());
    for (const glm::vec3& candidate : labs) {
        out.push_back(deltaECie1994(lab, candidate, K_L, K_C, K_H, K_1, K_2));
    }
    return out;
}

std::vector<float> deltaECie2000Matrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs, float K_l, float K_c,
                                       float K_h)
{
    std::vector<float> out;
    out.reserve(labs.size());
    for (const glm::vec3& candidate : labs) {
        out.push_back(deltaECie2000(lab, candidate, K_l, K_c, K_h));
    }
    return out;
}

std::vector<float> deltaECmcMatrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs, float p_l, float p_c)
{
    std::vector<float> out;
    out.reserve(labs.size());
    for (const glm::vec3& candidate : labs) {
        out.push_back(deltaECmc(lab, candidate, p_l, p_c));
    }
    return out;
}

namespace {

struct ParsedArrayTables {
    std::unordered_map<std::string, std::vector<float>> arrays;
    std::unordered_map<std::string, std::string> named_refs;
    float visual_density_thresh = 0.08f;
};

std::string trim(const std::string& s)
{
    size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
        start++;
    }
    size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        end--;
    }
    return s.substr(start, end - start);
}

std::optional<std::filesystem::path> resolve_assets_python_path()
{
    if (const char* env = std::getenv("SPACE_ASSETS_PATH")) {
        std::filesystem::path p(env);
        if (std::filesystem::exists(p / "python/lib/colormath")) {
            return p / "python/lib/colormath";
        }
    }
    std::filesystem::path cwd = std::filesystem::current_path();
    if (std::filesystem::exists(cwd / "assets/python/lib/colormath")) {
        return cwd / "assets/python/lib/colormath";
    }
    if (std::filesystem::exists(cwd / "../assets/python/lib/colormath")) {
        return cwd / "../assets/python/lib/colormath";
    }
    return std::nullopt;
}

ParsedArrayTables parse_python_arrays(const std::filesystem::path& path, const std::string& array_prefix)
{
    ParsedArrayTables tables;
    std::ifstream in(path);
    if (!in.is_open()) {
        throw std::runtime_error("failed to open " + path.string());
    }

    const std::regex number_re(R"(([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))");
    std::string line;
    std::string current_name;
    std::vector<float> current_values;
    bool in_array = false;
    bool in_ref_table = false;

    while (std::getline(in, line)) {
        std::string t = trim(line);
        if (t.rfind("VISUAL_DENSITY_THRESH", 0) == 0) {
            size_t eq = t.find('=');
            if (eq != std::string::npos) {
                tables.visual_density_thresh = std::stof(trim(t.substr(eq + 1)));
            }
        }

        if (!in_array) {
            size_t eq = t.find('=');
            if (eq != std::string::npos && t.find(array_prefix) != std::string::npos) {
                current_name = trim(t.substr(0, eq));
                current_values.clear();
                in_array = true;
                continue;
            }
        } else {
            if (t == "))" || t == "))," || t == "))}") {
                tables.arrays[to_lower(current_name)] = current_values;
                in_array = false;
                current_name.clear();
                current_values.clear();
                continue;
            }
            auto begin = std::sregex_iterator(t.begin(), t.end(), number_re);
            auto end = std::sregex_iterator();
            for (auto it = begin; it != end; ++it) {
                current_values.push_back(std::stof((*it).str()));
            }
            continue;
        }

        if (t.rfind("REF_ILLUM_TABLE", 0) == 0) {
            in_ref_table = true;
            continue;
        }
        if (in_ref_table) {
            if (t == "}") {
                in_ref_table = false;
                continue;
            }
            size_t key_start = t.find('\'');
            size_t key_end = key_start == std::string::npos ? std::string::npos : t.find('\'', key_start + 1);
            size_t colon = t.find(':');
            if (key_start != std::string::npos && key_end != std::string::npos && colon != std::string::npos) {
                std::string key = t.substr(key_start + 1, key_end - key_start - 1);
                std::string value = trim(t.substr(colon + 1));
                if (!value.empty() && value.back() == ',') {
                    value.pop_back();
                }
                tables.named_refs[to_lower(key)] = to_lower(trim(value));
            }
        }
    }

    return tables;
}

const ParsedArrayTables& spectral_tables()
{
    static ParsedArrayTables tables = []() {
        auto base = resolve_assets_python_path();
        if (!base.has_value()) {
            throw std::runtime_error("assets/python/lib/colormath not found; cannot load spectral constants");
        }
        return parse_python_arrays(base.value() / "spectral_constants.py", "numpy.array((");
    }();
    return tables;
}

const ParsedArrayTables& density_tables()
{
    static ParsedArrayTables tables = []() {
        auto base = resolve_assets_python_path();
        if (!base.has_value()) {
            throw std::runtime_error("assets/python/lib/colormath not found; cannot load density standards");
        }
        return parse_python_arrays(base.value() / "density_standards.py", "array((");
    }();
    return tables;
}

const std::vector<float>& require_array(const std::unordered_map<std::string, std::vector<float>>& arrays, const std::string& name)
{
    auto it = arrays.find(to_lower(name));
    if (it == arrays.end()) {
        throw std::invalid_argument("unknown array: " + name);
    }
    return it->second;
}

glm::mat3 rgb_to_xyz_matrix(const std::string& rgb_space)
{
    const std::string key = to_lower(rgb_space);
    if (key == "srgb") {
        return make_mat3_rows(0.412424f, 0.357579f, 0.180464f,
                              0.212656f, 0.715158f, 0.0721856f,
                              0.0193324f, 0.119193f, 0.950444f);
    }
    if (key == "adobergb" || key == "adobe-rgb") {
        return make_mat3_rows(0.576700f, 0.185556f, 0.188212f,
                              0.297361f, 0.627355f, 0.0752847f,
                              0.0270328f, 0.0706879f, 0.991248f);
    }
    if (key == "applergb" || key == "apple-rgb") {
        return make_mat3_rows(0.4497288f, 0.3162486f, 0.1844926f,
                              0.2446525f, 0.6720283f, 0.0833192f,
                              0.0251848f, 0.1411824f, 0.9224628f);
    }
    throw std::invalid_argument("unknown rgb space: " + rgb_space);
}

float rgb_gamma(const std::string& rgb_space)
{
    const std::string key = to_lower(rgb_space);
    if (key == "srgb") {
        return 2.2f;
    }
    if (key == "adobergb" || key == "adobe-rgb") {
        return 2.2f;
    }
    if (key == "applergb" || key == "apple-rgb") {
        return 1.8f;
    }
    throw std::invalid_argument("unknown rgb space: " + rgb_space);
}

glm::vec3 linearize_rgb_space(const glm::vec3& rgb, const std::string& rgb_space)
{
    if (to_lower(rgb_space) == "srgb") {
        return glm::vec3(gamma_expand(rgb.x), gamma_expand(rgb.y), gamma_expand(rgb.z));
    }
    const float g = rgb_gamma(rgb_space);
    return glm::vec3(std::pow(rgb.x, g), std::pow(rgb.y, g), std::pow(rgb.z, g));
}

glm::vec3 delinearize_rgb_space(const glm::vec3& rgb, const std::string& rgb_space)
{
    if (to_lower(rgb_space) == "srgb") {
        return glm::vec3(gamma_compress(rgb.x), gamma_compress(rgb.y), gamma_compress(rgb.z));
    }
    const float inv_g = 1.0f / rgb_gamma(rgb_space);
    return glm::vec3(std::pow(rgb.x, inv_g), std::pow(rgb.y, inv_g), std::pow(rgb.z, inv_g));
}

glm::vec3 rgb_to_xyz_space(const glm::vec3& rgb, const std::string& rgb_space)
{
    const glm::mat3 m = rgb_to_xyz_matrix(rgb_space);
    return m * linearize_rgb_space(rgb, rgb_space);
}

glm::vec3 xyz_to_rgb_space(const glm::vec3& xyz, const std::string& rgb_space)
{
    const glm::mat3 m_inv = glm::inverse(rgb_to_xyz_matrix(rgb_space));
    glm::vec3 linear = m_inv * xyz;
    linear = glm::clamp(linear, glm::vec3(0.0f), glm::vec3(1.0f));
    return delinearize_rgb_space(linear, rgb_space);
}

glm::vec3 hunt_xyz_to_rgb(const glm::vec3& xyz)
{
    const glm::mat3 m = make_mat3_rows(0.38971f, 0.68898f, -0.07868f,
                                       -0.22981f, 1.18340f, 0.04641f,
                                       0.0f, 0.0f, 1.0f);
    return m * xyz;
}

float hunt_fn(float i)
{
    return 40.0f * (std::pow(i, 0.73f) / (std::pow(i, 0.73f) + 2.0f));
}

} // namespace

glm::vec3 spectralToXyz(const std::vector<float>& spectral, const std::string& observer, const std::string& illuminant)
{
    if (spectral.size() != 50) {
        throw std::invalid_argument("spectral sample must have 50 values (340-830nm @ 10nm)");
    }

    const ParsedArrayTables& tables = spectral_tables();
    const auto ref_it = tables.named_refs.find(to_lower(illuminant));
    if (ref_it == tables.named_refs.end()) {
        throw std::invalid_argument("unknown spectral illuminant: " + illuminant);
    }

    const std::vector<float>& ref_illum = require_array(tables.arrays, ref_it->second);
    const std::vector<float>& std_x = require_array(tables.arrays, observer == "10" ? "stdobserv_x10" : "stdobserv_x2");
    const std::vector<float>& std_y = require_array(tables.arrays, observer == "10" ? "stdobserv_y10" : "stdobserv_y2");
    const std::vector<float>& std_z = require_array(tables.arrays, observer == "10" ? "stdobserv_z10" : "stdobserv_z2");

    float denom = 0.0f;
    float x_num = 0.0f;
    float y_num = 0.0f;
    float z_num = 0.0f;
    for (size_t i = 0; i < spectral.size(); ++i) {
        const float sample_ref = spectral[i] * ref_illum[i];
        denom += std_y[i] * ref_illum[i];
        x_num += sample_ref * std_x[i];
        y_num += sample_ref * std_y[i];
        z_num += sample_ref * std_z[i];
    }
    return glm::vec3(x_num / denom, y_num / denom, z_num / denom);
}

float ansiDensity(const std::vector<float>& spectral, const std::string& densityStandard)
{
    if (spectral.size() != 50) {
        throw std::invalid_argument("spectral sample must have 50 values (340-830nm @ 10nm)");
    }
    const ParsedArrayTables& tables = density_tables();
    const std::vector<float>& standard = require_array(tables.arrays, densityStandard);
    if (standard.size() != spectral.size()) {
        throw std::runtime_error("density standard/sample size mismatch");
    }

    float numerator = 0.0f;
    float denominator = 0.0f;
    for (size_t i = 0; i < spectral.size(); ++i) {
        numerator += spectral[i] * standard[i];
        denominator += standard[i];
    }
    return -std::log10(numerator / denominator);
}

float autoDensity(const std::vector<float>& spectral)
{
    const ParsedArrayTables& tables = density_tables();
    const float blue = ansiDensity(spectral, "ansi_status_t_blue");
    const float green = ansiDensity(spectral, "ansi_status_t_green");
    const float red = ansiDensity(spectral, "ansi_status_t_red");

    const float min_d = std::min({blue, green, red});
    const float max_d = std::max({blue, green, red});
    const float range = max_d - min_d;
    if (range <= tables.visual_density_thresh) {
        return ansiDensity(spectral, "iso_visual");
    }
    if (blue > green && blue > red) {
        return blue;
    }
    if (green > blue && green > red) {
        return green;
    }
    return red;
}

glm::vec4 convertColor(const glm::vec4& value, const std::string& sourceSpace, const std::string& targetSpace,
                       const std::string& throughRgbSpace, const std::string& sourceIlluminant,
                       const std::string& targetIlluminant, const std::string& observer)
{
    const std::string src = to_lower(sourceSpace);
    const std::string dst = to_lower(targetSpace);

    glm::vec3 xyz(0.0f);
    if (src == "xyz") {
        xyz = glm::vec3(value);
    } else if (src == "rgb") {
        xyz = rgb_to_xyz_space(glm::vec3(value), throughRgbSpace);
    } else if (src == "lab") {
        xyz = labToXyz(glm::vec3(value), observer, sourceIlluminant) / 100.0f;
    } else if (src == "lchab") {
        xyz = labToXyz(lchabToLab(glm::vec3(value)), observer, sourceIlluminant) / 100.0f;
    } else if (src == "luv") {
        xyz = luvToXyz(glm::vec3(value), observer, sourceIlluminant) / 100.0f;
    } else if (src == "lchuv") {
        xyz = luvToXyz(lchuvToLuv(glm::vec3(value)), observer, sourceIlluminant) / 100.0f;
    } else if (src == "xyy") {
        xyz = xyyToXyz(glm::vec3(value));
    } else if (src == "hsv") {
        xyz = rgb_to_xyz_space(hsvToRgb(glm::vec3(value)), throughRgbSpace);
    } else if (src == "hsl") {
        xyz = rgb_to_xyz_space(hslToRgb(glm::vec3(value)), throughRgbSpace);
    } else if (src == "cmy") {
        xyz = rgb_to_xyz_space(cmyToRgb(glm::vec3(value)), throughRgbSpace);
    } else if (src == "cmyk") {
        xyz = rgb_to_xyz_space(cmyToRgb(cmykToCmy(value)), throughRgbSpace);
    } else if (src == "ipt") {
        xyz = iptToXyz(glm::vec3(value)) / 100.0f;
    } else {
        throw std::invalid_argument("unsupported source space: " + sourceSpace);
    }

    const std::string src_illum = to_lower(sourceIlluminant);
    const std::string dst_illum = to_lower(targetIlluminant);
    if (src_illum != dst_illum) {
        xyz = adaptXyz(xyz * 100.0f, src_illum, dst_illum, observer, "bradford") / 100.0f;
    }

    if (dst == "xyz") {
        return glm::vec4(xyz, 0.0f);
    }
    if (dst == "rgb") {
        return glm::vec4(xyz_to_rgb_space(xyz, throughRgbSpace), 0.0f);
    }
    if (dst == "lab") {
        return glm::vec4(xyzToLab(xyz * 100.0f, observer, targetIlluminant), 0.0f);
    }
    if (dst == "lchab") {
        return glm::vec4(labToLchab(xyzToLab(xyz * 100.0f, observer, targetIlluminant)), 0.0f);
    }
    if (dst == "luv") {
        return glm::vec4(xyzToLuv(xyz * 100.0f, observer, targetIlluminant), 0.0f);
    }
    if (dst == "lchuv") {
        return glm::vec4(luvToLchuv(xyzToLuv(xyz * 100.0f, observer, targetIlluminant)), 0.0f);
    }
    if (dst == "xyy") {
        return glm::vec4(xyzToXyy(xyz), 0.0f);
    }
    if (dst == "hsv") {
        return glm::vec4(rgbToHsv(xyz_to_rgb_space(xyz, throughRgbSpace)), 0.0f);
    }
    if (dst == "hsl") {
        return glm::vec4(rgbToHsl(xyz_to_rgb_space(xyz, throughRgbSpace)), 0.0f);
    }
    if (dst == "cmy") {
        return glm::vec4(rgbToCmy(xyz_to_rgb_space(xyz, throughRgbSpace)), 0.0f);
    }
    if (dst == "cmyk") {
        return cmyToCmyk(rgbToCmy(xyz_to_rgb_space(xyz, throughRgbSpace)));
    }
    if (dst == "ipt") {
        return glm::vec4(xyzToIpt(xyz * 100.0f), 0.0f);
    }
    throw std::invalid_argument("unsupported target space: " + targetSpace);
}

std::map<std::string, float> modelNayatani95(float x, float y, float z, float x_n, float y_n, float z_n, float y_ob,
                                             float e_o, float e_or, float n)
{
    if (y_ob <= 0.18f) {
        throw std::invalid_argument("y-ob must be greater than 0.18");
    }
    const float l_o = y_ob * e_o / (100.0f * glm::pi<float>());
    const float l_or = y_ob * e_or / (100.0f * glm::pi<float>());
    const float x_o = x_n / (x_n + y_n + z_n);
    const float y_o = y_n / (x_n + y_n + z_n);

    const float xi = (0.48105f * x_o + 0.78841f * y_o - 0.08081f) / y_o;
    const float eta = (-0.27200f * x_o + 1.11962f * y_o + 0.04570f) / y_o;
    const float zeta = (0.91822f * (1.0f - x_o - y_o)) / y_o;
    const glm::vec3 rgb_0 = ((y_ob * e_o) / (100.0f * glm::pi<float>())) * glm::vec3(xi, eta, zeta);
    const glm::vec3 rgb = make_mat3_rows(0.40024f, 0.70760f, -0.08081f,
                                         -0.22630f, 1.16532f, 0.04570f,
                                         0.0f, 0.0f, 0.91822f) * glm::vec3(x, y, z);

    const auto scale_coeff = [](float a, float b) { return a >= (20.0f * b) ? 1.758f : 1.0f; };
    const auto beta1 = [](float v) { return (6.469f + 6.362f * std::pow(v, 0.4495f)) / (6.469f + std::pow(v, 0.4495f)); };
    const auto beta2 = [](float v) { return 0.7844f * (8.414f + 8.091f * std::pow(v, 0.5128f)) / (8.414f + std::pow(v, 0.5128f)); };
    const auto chromatic_strength = [](float angle) {
        float r = 0.9394f;
        r += -0.2478f * std::sin(angle);
        r += -0.0743f * std::sin(2.0f * angle);
        r += 0.0666f * std::sin(3.0f * angle);
        r += -0.0186f * std::sin(4.0f * angle);
        r += -0.0055f * std::cos(angle);
        r += -0.0521f * std::cos(2.0f * angle);
        r += -0.0573f * std::cos(3.0f * angle);
        r += -0.0061f * std::cos(4.0f * angle);
        return r;
    };

    const float e_r = scale_coeff(rgb.x, xi);
    const float e_g = scale_coeff(rgb.y, eta);
    const float beta_r = beta1(rgb_0.x);
    const float beta_g = beta1(rgb_0.y);
    const float beta_b = beta2(rgb_0.z);
    const float beta_l = beta1(l_or);

    float q = (2.0f / 3.0f) * beta_r * e_r * std::log10((rgb.x + n) / (20.0f * xi + n));
    q += (1.0f / 3.0f) * beta_g * e_g * std::log10((rgb.y + n) / (20.0f * eta + n));
    q *= 41.69f / beta_l;

    float t = beta_r * std::log10((rgb.x + n) / (20.0f * xi + n));
    t += -(12.0f / 11.0f) * beta_g * std::log10((rgb.y + n) / (20.0f * eta + n));
    t += (1.0f / 11.0f) * beta_b * std::log10((rgb.z + n) / (20.0f * zeta + n));

    float p = (1.0f / 9.0f) * beta_r * std::log10((rgb.x + n) / (20.0f * xi + n));
    p += (1.0f / 9.0f) * beta_g * std::log10((rgb.y + n) / (20.0f * eta + n));
    p += -(2.0f / 9.0f) * beta_b * std::log10((rgb.z + n) / (20.0f * zeta + n));

    const float brightness = (50.0f / beta_l) * ((2.0f / 3.0f) * beta_r + (1.0f / 3.0f) * beta_g) + q;
    const float lightness_achromatic = q + 50.0f;
    const float hue_angle_rad = std::atan2(p, t);
    const float hue_angle = std::fmod(glm::degrees(hue_angle_rad) + 360.0f, 360.0f);
    const float e_s_theta = chromatic_strength(hue_angle_rad);
    const float sat_rg = (488.93f / beta_l) * e_s_theta * t;
    const float sat_yb = (488.93f / beta_l) * e_s_theta * p;
    const float saturation = std::sqrt(sat_rg * sat_rg + sat_yb * sat_yb);
    const float chroma = std::pow(lightness_achromatic / 50.0f, 0.7f) * saturation;
    float brightness_ideal_white = (2.0f / 3.0f) * beta_r * 1.758f * std::log10((100.0f * xi + n) / (20.0f * xi + n));
    brightness_ideal_white += (1.0f / 3.0f) * beta_g * 1.758f * std::log10((100.0f * eta + n) / (20.0f * eta + n));
    brightness_ideal_white *= 41.69f / beta_l;
    brightness_ideal_white += (50.0f / beta_l) * (2.0f / 3.0f) * beta_r;
    brightness_ideal_white += (50.0f / beta_l) * (1.0f / 3.0f) * beta_g;
    const float colorfulness = chroma * brightness_ideal_white / 100.0f;

    return {
        {"hue-angle", hue_angle},
        {"chroma", chroma},
        {"saturation", saturation},
        {"brightness", brightness},
        {"colorfulness", colorfulness},
    };
}

std::map<std::string, float> modelHunt(float x, float y, float z, float x_b, float y_b, float z_b, float x_w, float y_w,
                                       float z_w, float l_a, float n_c, float n_b)
{
    const glm::vec3 xyz(x, y, z);
    const glm::vec3 xyz_w(x_w, y_w, z_w);
    const glm::vec3 xyz_b(x_b, y_b, z_b);
    const float n_cb = 0.725f * std::pow(y_w / y_b, 0.2f);
    const float n_bb = n_cb;

    const float k = 1.0f / (5.0f * l_a + 1.0f);
    const float f_l = 0.2f * std::pow(k, 4.0f) * (5.0f * l_a) + 0.1f * std::pow(1.0f - std::pow(k, 4.0f), 2.0f) *
                                                                   std::pow(5.0f * l_a, 1.0f / 3.0f);

    auto adaptation = [&](const glm::vec3& c) {
        glm::vec3 rgb = hunt_xyz_to_rgb(c);
        glm::vec3 rgb_w = hunt_xyz_to_rgb(xyz_w);
        glm::vec3 h_rgb = 3.0f * rgb_w / (rgb_w.x + rgb_w.y + rgb_w.z);
        glm::vec3 f_rgb = (1.0f + std::pow(l_a, 1.0f / 3.0f) + h_rgb) /
                          (1.0f + std::pow(l_a, 1.0f / 3.0f) + (1.0f / h_rgb));
        glm::vec3 rgb_bleach = (1e7f) / ((1e7f) + 5.0f * l_a * (rgb_w / 100.0f));
        return glm::vec3(1.0f) + rgb_bleach * glm::vec3(hunt_fn(f_l * f_rgb.x * rgb.x / rgb_w.x),
                                                        hunt_fn(f_l * f_rgb.y * rgb.y / rgb_w.y),
                                                        hunt_fn(f_l * f_rgb.z * rgb.z / rgb_w.z));
    };

    const glm::vec3 rgb_a = adaptation(xyz);
    const glm::vec3 rgb_aw = adaptation(xyz_w);
    const float c1 = rgb_a.x - rgb_a.y;
    const float c2 = rgb_a.y - rgb_a.z;
    const float c3 = rgb_a.z - rgb_a.x;

    const float hue_angle = std::fmod(glm::degrees(std::atan2(0.5f * (c2 - c3) / 4.5f, c1 - c2 / 11.0f)) + 360.0f, 360.0f);
    const float e_s = hue_angle < 20.14f ? 0.856f - (hue_angle / 20.14f) * 0.056f :
                       (hue_angle > 237.53f ? 0.856f + 0.344f * (360.0f - hue_angle) / (360.0f - 237.53f) :
                        glm::mix(hue_angle < 90.0f ? 0.8f : (hue_angle < 164.25f ? 0.7f : 1.0f),
                                 hue_angle < 90.0f ? 0.7f : (hue_angle < 164.25f ? 1.0f : 1.2f), 0.5f));
    const float f_t = l_a / (l_a + 0.1f);
    const float m_yb = 100.0f * (0.5f * (c2 - c3) / 4.5f) * (e_s * (10.0f / 13.0f) * n_c * n_cb * f_t);
    const float m_rg = 100.0f * (c1 - (c2 / 11.0f)) * (e_s * (10.0f / 13.0f) * n_c * n_cb);
    const float m = std::sqrt(m_rg * m_rg + m_yb * m_yb);
    const float saturation = 50.0f * m / (rgb_a.x + rgb_a.y + rgb_a.z);

    const float aa = 2.0f * rgb_a.x + rgb_a.y + rgb_a.z / 20.0f - 3.05f + 1.0f;
    const float aaw = 2.0f * rgb_aw.x + rgb_aw.y + rgb_aw.z / 20.0f - 3.05f + 1.0f;
    const float a = n_bb * (aa + std::sqrt(1.0f + 0.3f * 0.3f));
    const float aw = n_bb * (aaw + std::sqrt(1.0f + 0.3f * 0.3f));
    const float n1 = std::sqrt(7.0f * aw) / (5.33f * std::pow(n_b, 0.13f));
    const float n2 = (7.0f * aw * std::pow(n_b, 0.362f)) / 200.0f;
    const float brightness = std::pow(7.0f * (a + m / 100.0f), 0.6f) * n1 - n2;
    const float brightness_w = std::pow(7.0f * (aw + m / 100.0f), 0.6f) * n1 - n2;
    const float lightness = 100.0f * std::pow(brightness / brightness_w, 1.0f + std::sqrt(y_b / y_w));
    const float chroma = 2.44f * std::pow(saturation, 0.69f) * std::pow(brightness / brightness_w, y_b / y_w) *
                         (1.64f - std::pow(0.29f, y_b / y_w));
    const float colorfulness = std::pow(f_l, 0.15f) * chroma;

    return {{"hue-angle", hue_angle},
            {"chroma", chroma},
            {"saturation", saturation},
            {"brightness", brightness},
            {"colorfulness", colorfulness},
            {"lightness", lightness}};
}

std::map<std::string, float> modelRlab(float x, float y, float z, float x_n, float y_n, float z_n, float y_n_abs,
                                       float sigma, float d)
{
    const glm::vec3 xyz(x, y, z);
    const glm::vec3 xyz_n(x_n, y_n, z_n);
    glm::vec3 lms = hunt_xyz_to_rgb(xyz);
    glm::vec3 lms_n = hunt_xyz_to_rgb(xyz_n);
    glm::vec3 lms_e = (3.0f * lms_n) / (lms_n.x + lms_n.y + lms_n.z);
    glm::vec3 lms_p = (1.0f + std::pow(y_n_abs, 1.0f / 3.0f) + lms_e) /
                      (1.0f + std::pow(y_n_abs, 1.0f / 3.0f) + 1.0f / lms_e);
    glm::vec3 lms_a = (lms_p + d * (1.0f - lms_p)) / lms_n;
    glm::mat3 A(1.0f);
    A[0][0] = lms_a.x;
    A[1][1] = lms_a.y;
    A[2][2] = lms_a.z;
    glm::mat3 R = make_mat3_rows(1.9569f, -1.1882f, 0.2313f,
                                 0.3612f, 0.6388f, 0.0f,
                                 0.0f, 0.0f, 1.0f);
    glm::mat3 hunt_m = make_mat3_rows(0.38971f, 0.68898f, -0.07868f,
                                      -0.22981f, 1.18340f, 0.04641f,
                                      0.0f, 0.0f, 1.0f);
    glm::vec3 xyz_ref = R * A * hunt_m * xyz;
    const float lightness = 100.0f * std::pow(xyz_ref.y, sigma);
    const float a = 430.0f * (std::pow(xyz_ref.x, sigma) - std::pow(xyz_ref.y, sigma));
    const float b = 170.0f * (std::pow(xyz_ref.y, sigma) - std::pow(xyz_ref.z, sigma));
    const float hue = std::fmod(glm::degrees(std::atan2(b, a)) + 360.0f, 360.0f);
    const float chroma = std::sqrt(a * a + b * b);
    const float saturation = chroma / lightness;
    return {{"hue-angle", hue}, {"chroma", chroma}, {"saturation", saturation}, {"lightness", lightness}, {"a", a}, {"b", b}};
}

std::map<std::string, float> modelAtd95(float x, float y, float z, float x_0, float y_0, float z_0, float y_0_abs,
                                        float k_1, float k_2, float sigma)
{
    auto scale_to_luminance = [](const glm::vec3& xyz, float abs_l) {
        return 18.0f * glm::pow((abs_l * xyz / 100.0f), glm::vec3(0.8f));
    };
    auto xyz_to_lms = [](const glm::vec3& xyz) {
        float l = std::pow(0.66f * (0.2435f * xyz.x + 0.8524f * xyz.y - 0.0516f * xyz.z), 0.7f) + 0.024f;
        float m = std::pow(-0.3954f * xyz.x + 1.1642f * xyz.y + 0.0837f * xyz.z, 0.7f) + 0.036f;
        float s = std::pow(0.43f * (0.04f * xyz.y + 0.6225f * xyz.z), 0.7f) + 0.31f;
        return glm::vec3(l, m, s);
    };
    auto final_response = [](float v) { return v / (200.0f + std::abs(v)); };

    glm::vec3 xyz = scale_to_luminance(glm::vec3(x, y, z), y_0_abs);
    glm::vec3 xyz_0 = scale_to_luminance(glm::vec3(x_0, y_0, z_0), y_0_abs);
    glm::vec3 lms = xyz_to_lms(xyz);
    glm::vec3 xyz_a = k_1 * xyz + k_2 * xyz_0;
    glm::vec3 lms_a = xyz_to_lms(xyz_a);
    glm::vec3 lms_g = lms * (sigma / (sigma + lms_a));

    float a_1i = 3.57f * lms_g.x + 2.64f * lms_g.y;
    float t_1i = 7.18f * lms_g.x - 6.21f * lms_g.y;
    float d_1i = -0.7f * lms_g.x + 0.085f * lms_g.y + lms_g.z;
    float a_2i = 0.09f * a_1i;
    float t_2i = 0.43f * t_1i + 0.76f * d_1i;
    float d_2i = d_1i;

    const float a_1 = final_response(a_1i);
    const float t_1 = final_response(t_1i);
    const float d_1 = final_response(d_1i);
    const float a_2 = final_response(a_2i);
    const float t_2 = final_response(t_2i);
    const float d_2 = final_response(d_2i);

    const float brightness = std::sqrt(a_1 * a_1 + t_1 * t_1 + d_1 * d_1);
    const float saturation = std::sqrt(t_2 * t_2 + d_2 * d_2) / a_2;
    const float hue = t_2 / d_2;
    return {{"hue", hue}, {"brightness", brightness}, {"saturation", saturation}};
}

std::map<std::string, float> modelLlab(float x, float y, float z, float x_0, float y_0, float z_0, float y_b, float f_s,
                                       float f_l, float f_c, float l, float d)
{
    auto xyz_to_rgb = [](const glm::vec3& xyz) {
        const glm::mat3 m = make_mat3_rows(0.8951f, 0.2664f, -0.1614f,
                                           -0.7502f, 1.7135f, 0.0367f,
                                           0.0389f, -0.0685f, 1.0296f);
        return m * (xyz / xyz.y);
    };
    const glm::vec3 xyz(x, y, z);
    const glm::vec3 xyz_0(x_0, y_0, z_0);
    const glm::vec3 rgb = xyz_to_rgb(xyz);
    const glm::vec3 rgb_0 = xyz_to_rgb(xyz_0);
    const glm::vec3 rgb_0r = xyz_to_rgb(glm::vec3(95.05f, 100.0f, 108.88f));

    const float beta = std::pow(rgb_0.z / rgb_0r.z, 0.0834f);
    const float r_r = (d * (rgb_0r.x / rgb_0.x) + 1.0f - d) * rgb.x;
    const float g_r = (d * (rgb_0r.y / rgb_0.y) + 1.0f - d) * rgb.y;
    const float b_r = (d * (rgb_0r.z / std::pow(rgb_0.z, beta)) + 1.0f - d) * std::pow(std::abs(rgb.z), beta);

    const glm::mat3 m_inv = make_mat3_rows(0.987f, -0.1471f, 0.16f,
                                           0.4323f, 0.5184f, 0.0493f,
                                           -0.0085f, 0.04f, 0.9685f);
    const glm::vec3 xyz_r = m_inv * (glm::vec3(r_r, g_r, b_r) * y);

    auto f = [f_s](float w) {
        if (w > 0.008856f) {
            return std::pow(w, 1.0f / f_s);
        }
        return (((std::pow(0.008856f, 1.0f / f_s)) - (16.0f / 116.0f)) / 0.008856f) * w + (16.0f / 116.0f);
    };

    const float zc = 1.0f + f_l * std::sqrt(y_b / 100.0f);
    const float lightness = 116.0f * std::pow(f(xyz_r.y / 100.0f), zc) - 16.0f;
    const float a = 500.0f * (f(xyz_r.x / 95.05f) - f(xyz_r.y / 100.0f));
    const float b = 200.0f * (f(xyz_r.y / 100.0f) - f(xyz_r.z / 108.88f));
    const float c = std::sqrt(a * a + b * b);
    const float chroma = 25.0f * std::log(1.0f + 0.05f * c);
    const float s_c = 1.0f + 0.47f * std::log10(l) - 0.057f * std::pow(std::log10(l), 2.0f);
    const float s_m = 0.7f + 0.02f * lightness - 0.0002f * lightness * lightness;
    const float c_l = chroma * s_m * s_c * f_c;
    const float hue = std::fmod(glm::degrees(std::atan2(b, a)) + 360.0f, 360.0f);

    return {{"hue-angle", hue},
            {"chroma", chroma},
            {"saturation", chroma / lightness},
            {"lightness", lightness},
            {"a-l", c_l * std::cos(glm::radians(hue))},
            {"b-l", c_l * std::sin(glm::radians(hue))}};
}

std::map<std::string, float> modelCiecam02(float x, float y, float z, float x_w, float y_w, float z_w, float y_b,
                                           float l_a, float c, float n_c, float f, bool d)
{
    const glm::mat3 M_CAT02 = make_mat3_rows(0.7328f, 0.4296f, -0.1624f,
                                             -0.7036f, 1.6975f, 0.0061f,
                                             0.0030f, 0.0136f, 0.9834f);
    const glm::mat3 M_CAT02_inv = glm::inverse(M_CAT02);
    const glm::mat3 M_HPE = make_mat3_rows(0.38971f, 0.68898f, -0.07868f,
                                           -0.22981f, 1.18340f, 0.04641f,
                                           0.0f, 0.0f, 1.0f);

    glm::vec3 xyz(x, y, z);
    glm::vec3 xyz_w(x_w, y_w, z_w);
    float D = d ? 1.0f : f * (1.0f - (1.0f / 3.6f) * std::exp((-l_a - 42.0f) / 92.0f));
    float k = 1.0f / (5.0f * l_a + 1.0f);
    float F_L = 0.2f * std::pow(k, 4.0f) * 5.0f * l_a + 0.1f * std::pow(1.0f - std::pow(k, 4.0f), 2.0f) *
                                                         std::pow(5.0f * l_a, 1.0f / 3.0f);
    float n = y_b / y_w;
    float n_bb = 0.725f * std::pow(n, -0.2f);
    float zc = 1.48f + std::sqrt(n);

    auto adapt = [&](const glm::vec3& c_xyz, const glm::vec3& w_xyz) {
        glm::vec3 rgb = M_CAT02 * c_xyz;
        glm::vec3 rgb_w = M_CAT02 * w_xyz;
        glm::vec3 rgb_c = ((100.0f * D / rgb_w) + (1.0f - D)) * rgb;
        glm::vec3 rgb_p = M_HPE * M_CAT02_inv * rgb_c;
        glm::vec3 nonlin = 0.1f + (400.0f * glm::pow((F_L * rgb_p / 100.0f), glm::vec3(0.42f))) /
                                      (27.13f + glm::pow((F_L * rgb_p / 100.0f), glm::vec3(0.42f)));
        return nonlin;
    };

    glm::vec3 rgb_a = adapt(xyz, xyz_w);
    glm::vec3 rgb_aw = adapt(xyz_w, xyz_w);
    float a = rgb_a.x - 12.0f * rgb_a.y / 11.0f + rgb_a.z / 11.0f;
    float b = (rgb_a.x + rgb_a.y - 2.0f * rgb_a.z) / 9.0f;
    float h = glm::degrees(std::atan2(b, a));
    float e_t = 0.25f * (std::cos(2.0f + glm::radians(h)) + 3.8f);
    float A = (2.0f * rgb_a.x + rgb_a.y + rgb_a.z / 20.0f - 0.305f) * n_bb;
    float A_w = (2.0f * rgb_aw.x + rgb_aw.y + rgb_aw.z / 20.0f - 0.305f) * n_bb;
    float J = 100.0f * std::pow(A / A_w, c * zc);
    float Q = (4.0f / c) * std::sqrt(J / 100.0f) * (A_w + 4.0f) * std::pow(F_L, 0.25f);
    float t = ((50000.0f / 13.0f) * n_c * n_bb * e_t * std::sqrt(a * a + b * b)) /
              (rgb_a.x + rgb_a.y + (21.0f / 20.0f) * rgb_a.z);
    float C = std::pow(t, 0.9f) * std::sqrt(J / 100.0f) * std::pow(1.64f - std::pow(0.29f, n), 0.73f);
    float M = C * std::pow(F_L, 0.25f);
    float s = 100.0f * std::sqrt(M / Q);
    return {{"hue-angle", h},
            {"chroma", C},
            {"saturation", s},
            {"lightness", J},
            {"brightness", Q},
            {"colorfulness", M},
            {"a", a},
            {"b", b}};
}

std::map<std::string, float> modelCiecam02m1(float x, float y, float z, float x_w, float y_w, float z_w, float x_b,
                                             float y_b, float z_b, float l_a, float c, float n_c, float f, float p,
                                             bool d)
{
    // Modified white point for simultaneous contrast/assimilation then reuse CIECAM02 implementation.
    const glm::mat3 M_CAT02 = make_mat3_rows(0.7328f, 0.4296f, -0.1624f,
                                             -0.7036f, 1.6975f, 0.0061f,
                                             0.0030f, 0.0136f, 0.9834f);
    glm::vec3 rgb = M_CAT02 * glm::vec3(x, y, z);
    glm::vec3 rgb_b = M_CAT02 * glm::vec3(x_b, y_b, z_b);
    glm::vec3 rgb_w = M_CAT02 * glm::vec3(x_w, y_w, z_w);
    glm::vec3 p_rgb = rgb / rgb_b;
    glm::vec3 rgb_w_adj = rgb_w * glm::sqrt(((1.0f - p) * p_rgb + (1.0f + p) / p_rgb) /
                                            ((1.0f + p) * p_rgb + (1.0f - p) / p_rgb));
    const glm::mat3 M_CAT02_inv = glm::inverse(M_CAT02);
    glm::vec3 xyz_w_adj = M_CAT02_inv * rgb_w_adj;
    return modelCiecam02(x, y, z, xyz_w_adj.x, xyz_w_adj.y, xyz_w_adj.z, y_b, l_a, c, n_c, f, d);
}

std::vector<std::string> getConversionPath(const std::string& sourceSpace, const std::string& targetSpace)
{
    const std::string src = to_lower(sourceSpace);
    const std::string dst = to_lower(targetSpace);
    if (src == dst) {
        return {src};
    }

    const std::unordered_map<std::string, std::vector<std::string>> edges = {
        {"rgb", {"xyz", "hsv", "hsl", "cmy"}},
        {"xyz", {"rgb", "lab", "luv", "xyy", "ipt"}},
        {"lab", {"xyz", "lchab"}},
        {"lchab", {"lab"}},
        {"luv", {"xyz", "lchuv"}},
        {"lchuv", {"luv"}},
        {"xyy", {"xyz"}},
        {"hsv", {"rgb"}},
        {"hsl", {"rgb"}},
        {"cmy", {"rgb", "cmyk"}},
        {"cmyk", {"cmy"}},
        {"ipt", {"xyz"}},
    };

    std::vector<std::string> queue = {src};
    std::unordered_map<std::string, std::string> prev;
    prev[src] = "";
    for (size_t i = 0; i < queue.size(); ++i) {
        const std::string node = queue[i];
        auto it = edges.find(node);
        if (it == edges.end()) {
            continue;
        }
        for (const std::string& next : it->second) {
            if (prev.find(next) == prev.end()) {
                prev[next] = node;
                queue.push_back(next);
            }
        }
    }
    if (prev.find(dst) == prev.end()) {
        throw std::invalid_argument("no conversion path from " + sourceSpace + " to " + targetSpace);
    }
    std::vector<std::string> path;
    for (std::string cur = dst; !cur.empty(); cur = prev[cur]) {
        path.push_back(cur);
    }
    std::reverse(path.begin(), path.end());
    return path;
}

bool canConvert(const std::string& sourceSpace, const std::string& targetSpace)
{
    try {
        (void)getConversionPath(sourceSpace, targetSpace);
        return true;
    } catch (...) {
        return false;
    }
}

glm::vec3 rgbToUpscaled(const glm::vec3& rgb)
{
    return glm::vec3(std::floor(0.5f + rgb.x * 255.0f),
                     std::floor(0.5f + rgb.y * 255.0f),
                     std::floor(0.5f + rgb.z * 255.0f));
}

std::string rgbToHex(const glm::vec3& rgb)
{
    glm::vec3 v = rgbToUpscaled(rgb);
    std::ostringstream out;
    out << '#'
        << std::hex << std::nouppercase
        << std::setfill('0') << std::setw(2) << std::clamp(static_cast<int>(v.x), 0, 255)
        << std::setfill('0') << std::setw(2) << std::clamp(static_cast<int>(v.y), 0, 255)
        << std::setfill('0') << std::setw(2) << std::clamp(static_cast<int>(v.z), 0, 255);
    return out.str();
}

glm::vec3 rgbFromHex(const std::string& hex)
{
    std::string s = trim(hex);
    if (!s.empty() && s[0] == '#') {
        s = s.substr(1);
    }
    if (s.size() != 6) {
        throw std::invalid_argument("hex color must be #RRGGBB");
    }
    auto parse_byte = [&](size_t off) -> int {
        return std::stoi(s.substr(off, 2), nullptr, 16);
    };
    return glm::vec3(parse_byte(0) / 255.0f, parse_byte(2) / 255.0f, parse_byte(4) / 255.0f);
}

glm::vec3 clampRgb(const glm::vec3& rgb)
{
    return glm::clamp(rgb, glm::vec3(0.0f), glm::vec3(1.0f));
}
