#include "colorspacious.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_map>

#include <glm/gtc/constants.hpp>

namespace {

std::string to_lower(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
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

float sign_of(float value)
{
    if (value > 0.0f) {
        return 1.0f;
    }
    if (value < 0.0f) {
        return -1.0f;
    }
    return 0.0f;
}

float mod_360(float value)
{
    float out = std::fmod(value, 360.0f);
    if (out < 0.0f) {
        out += 360.0f;
    }
    return out;
}

constexpr std::array<float, 5> H_I = {0.0f, 100.0f, 200.0f, 300.0f, 400.0f};
constexpr std::array<float, 5> h_i = {20.14f, 90.00f, 164.25f, 237.53f, 380.14f};
constexpr std::array<float, 5> e_i = {0.8f, 0.7f, 1.0f, 1.2f, 0.8f};

const glm::mat3 M_CAT02 = make_mat3_rows(0.7328f, 0.4296f, -0.1624f,
                                          -0.7036f, 1.6975f, 0.0061f,
                                          0.0030f, 0.0136f, 0.9834f);
const glm::mat3 M_HPE = make_mat3_rows(0.38971f, 0.68898f, -0.07868f,
                                        -0.22981f, 1.18340f, 0.04641f,
                                        0.0f, 0.0f, 1.0f);
const glm::mat3 M_CAT02_inv = glm::inverse(M_CAT02);
const glm::mat3 M_HPE_M_CAT02_inv = M_HPE * M_CAT02_inv;
const glm::mat3 M_CAT02_M_HPE_inv = M_CAT02 * glm::inverse(M_HPE);

struct Ciecam02Precomputed {
    float D;
    glm::vec3 D_RGB;
    float F_L;
    float n;
    float z;
    float N_bb;
    float N_cb;
    float A_w;
};

Ciecam02Precomputed precompute(const Ciecam02Space& space)
{
    Ciecam02Precomputed out {};
    const float F = space.surround.F;
    const float c = space.surround.c;
    (void)c;

    const glm::vec3 RGB_w = M_CAT02 * space.XYZ100_w;
    out.D = F * (1.0f - (1.0f / 3.6f) * std::exp((-space.L_A - 42.0f) / 92.0f));
    out.D = std::clamp(out.D, 0.0f, 1.0f);
    out.D_RGB = out.D * (space.XYZ100_w.y / RGB_w) + (1.0f - out.D);

    const float k = 1.0f / (5.0f * space.L_A + 1.0f);
    out.F_L = 0.2f * std::pow(k, 4.0f) * (5.0f * space.L_A)
               + 0.1f * std::pow(1.0f - std::pow(k, 4.0f), 2.0f) * std::pow(5.0f * space.L_A, 1.0f / 3.0f);
    out.n = space.Y_b / space.XYZ100_w.y;
    out.z = 1.48f + std::sqrt(out.n);
    out.N_bb = 0.725f * std::pow(1.0f / out.n, 0.2f);
    out.N_cb = out.N_bb;

    const glm::vec3 RGB_wc = out.D_RGB * RGB_w;
    const glm::vec3 RGBprime_w = M_HPE_M_CAT02_inv * RGB_wc;
    const glm::vec3 tmp = glm::pow((out.F_L * RGBprime_w) / 100.0f, glm::vec3(0.42f));
    const glm::vec3 RGBprime_aw = 400.0f * (tmp / (tmp + 27.13f)) + 0.1f;
    out.A_w = (glm::dot(glm::vec3(2.0f, 1.0f, 1.0f / 20.0f), RGBprime_aw) - 0.305f) * out.N_bb;
    return out;
}

float ciecam_h_to_H(float h)
{
    const float hprime = (h < h_i[0]) ? (h + 360.0f) : h;
    size_t i = 0;
    while (i + 1 < h_i.size() && hprime >= h_i[i + 1]) {
        i++;
    }
    if (i + 1 >= h_i.size()) {
        i = h_i.size() - 2;
    }
    const float tmp = (hprime - h_i[i]) / e_i[i];
    return H_I[i] + ((100.0f * tmp) / (tmp + (h_i[i + 1] - hprime) / e_i[i + 1]));
}

float ciecam_H_to_h(float H)
{
    size_t i = 0;
    while (i + 1 < H_I.size() && H >= H_I[i + 1]) {
        i++;
    }
    if (i + 1 >= H_I.size()) {
        i = H_I.size() - 2;
    }

    const float num1 = (H - H_I[i]) * (e_i[i + 1] * h_i[i] - e_i[i] * h_i[i + 1]);
    const float num2 = -100.0f * h_i[i] * e_i[i + 1];
    const float denom1 = (H - H_I[i]) * (e_i[i + 1] - e_i[i]);
    const float denom2 = -100.0f * e_i[i + 1];
    float hprime = (num1 + num2) / (denom1 + denom2);
    if (hprime > 360.0f) {
        hprime -= 360.0f;
    }
    return hprime;
}

void require_exactly_one(const std::map<std::string, float>& values,
                         const std::string& a,
                         const std::string& b,
                         const std::string& c = "")
{
    int count = 0;
    if (values.find(a) != values.end()) {
        count++;
    }
    if (values.find(b) != values.end()) {
        count++;
    }
    if (!c.empty() && values.find(c) != values.end()) {
        count++;
    }
    if (count != 1) {
        if (c.empty()) {
            throw std::invalid_argument("exactly one of " + a + ", " + b + " is required");
        }
        throw std::invalid_argument("exactly one of " + a + ", " + b + ", " + c + " is required");
    }
}

std::array<glm::mat3, 11> protanomaly_tables()
{
    return {
        make_mat3_rows(1.000000f, 0.000000f, -0.000000f, 0.000000f, 1.000000f, 0.000000f, -0.000000f, -0.000000f, 1.000000f),
        make_mat3_rows(0.856167f, 0.182038f, -0.038205f, 0.029342f, 0.955115f, 0.015544f, -0.002880f, -0.001563f, 1.004443f),
        make_mat3_rows(0.734766f, 0.334872f, -0.069637f, 0.051840f, 0.919198f, 0.028963f, -0.004928f, -0.004209f, 1.009137f),
        make_mat3_rows(0.630323f, 0.465641f, -0.095964f, 0.069181f, 0.890046f, 0.040773f, -0.006308f, -0.007724f, 1.014032f),
        make_mat3_rows(0.539009f, 0.579343f, -0.118352f, 0.082546f, 0.866121f, 0.051332f, -0.007136f, -0.011959f, 1.019095f),
        make_mat3_rows(0.458064f, 0.679578f, -0.137642f, 0.092785f, 0.846313f, 0.060902f, -0.007494f, -0.016807f, 1.024301f),
        make_mat3_rows(0.385450f, 0.769005f, -0.154455f, 0.100526f, 0.829802f, 0.069673f, -0.007442f, -0.022190f, 1.029632f),
        make_mat3_rows(0.319627f, 0.849633f, -0.169261f, 0.106241f, 0.815969f, 0.077790f, -0.007025f, -0.028051f, 1.035076f),
        make_mat3_rows(0.259411f, 0.923008f, -0.182420f, 0.110296f, 0.804340f, 0.085364f, -0.006276f, -0.034346f, 1.040622f),
        make_mat3_rows(0.203876f, 0.990338f, -0.194214f, 0.112975f, 0.794542f, 0.092483f, -0.005222f, -0.041043f, 1.046265f),
        make_mat3_rows(0.152286f, 1.052583f, -0.204868f, 0.114503f, 0.786281f, 0.099216f, -0.003882f, -0.048116f, 1.051998f),
    };
}

std::array<glm::mat3, 11> deuteranomaly_tables()
{
    return {
        make_mat3_rows(1.000000f, 0.000000f, -0.000000f, 0.000000f, 1.000000f, 0.000000f, -0.000000f, -0.000000f, 1.000000f),
        make_mat3_rows(0.866435f, 0.177704f, -0.044139f, 0.049567f, 0.939063f, 0.011370f, -0.003453f, 0.007233f, 0.996220f),
        make_mat3_rows(0.760729f, 0.319078f, -0.079807f, 0.090568f, 0.889315f, 0.020117f, -0.006027f, 0.013325f, 0.992702f),
        make_mat3_rows(0.675425f, 0.433850f, -0.109275f, 0.125303f, 0.847755f, 0.026942f, -0.007950f, 0.018572f, 0.989378f),
        make_mat3_rows(0.605511f, 0.528560f, -0.134071f, 0.155318f, 0.812366f, 0.032316f, -0.009376f, 0.023176f, 0.986200f),
        make_mat3_rows(0.547494f, 0.607765f, -0.155259f, 0.181692f, 0.781742f, 0.036566f, -0.010410f, 0.027275f, 0.983136f),
        make_mat3_rows(0.498864f, 0.674741f, -0.173604f, 0.205199f, 0.754872f, 0.039929f, -0.011131f, 0.030969f, 0.980162f),
        make_mat3_rows(0.457771f, 0.731899f, -0.189670f, 0.226409f, 0.731012f, 0.042579f, -0.011595f, 0.034333f, 0.977261f),
        make_mat3_rows(0.422823f, 0.781057f, -0.203881f, 0.245752f, 0.709602f, 0.044646f, -0.011843f, 0.037423f, 0.974421f),
        make_mat3_rows(0.392952f, 0.823610f, -0.216562f, 0.263559f, 0.690210f, 0.046232f, -0.011910f, 0.040281f, 0.971630f),
        make_mat3_rows(0.367322f, 0.860646f, -0.227968f, 0.280085f, 0.672501f, 0.047413f, -0.011820f, 0.042940f, 0.968881f),
    };
}

std::array<glm::mat3, 11> tritanomaly_tables()
{
    return {
        make_mat3_rows(1.000000f, 0.000000f, -0.000000f, 0.000000f, 1.000000f, 0.000000f, -0.000000f, -0.000000f, 1.000000f),
        make_mat3_rows(0.926670f, 0.092514f, -0.019184f, 0.021191f, 0.964503f, 0.014306f, 0.008437f, 0.054813f, 0.936750f),
        make_mat3_rows(0.895720f, 0.133330f, -0.029050f, 0.029997f, 0.945400f, 0.024603f, 0.013027f, 0.104707f, 0.882266f),
        make_mat3_rows(0.905871f, 0.127791f, -0.033662f, 0.026856f, 0.941251f, 0.031893f, 0.013410f, 0.148296f, 0.838294f),
        make_mat3_rows(0.948035f, 0.089490f, -0.037526f, 0.014364f, 0.946792f, 0.038844f, 0.010853f, 0.193991f, 0.795156f),
        make_mat3_rows(1.017277f, 0.027029f, -0.044306f, -0.006113f, 0.958479f, 0.047634f, 0.006379f, 0.248708f, 0.744913f),
        make_mat3_rows(1.104996f, -0.046633f, -0.058363f, -0.032137f, 0.971635f, 0.060503f, 0.001336f, 0.317922f, 0.680742f),
        make_mat3_rows(1.193214f, -0.109812f, -0.083402f, -0.058496f, 0.979410f, 0.079086f, -0.002346f, 0.403492f, 0.598854f),
        make_mat3_rows(1.257728f, -0.139648f, -0.118081f, -0.078003f, 0.975409f, 0.102594f, -0.003316f, 0.501214f, 0.502102f),
        make_mat3_rows(1.278864f, -0.125333f, -0.153531f, -0.084748f, 0.957674f, 0.127074f, -0.000989f, 0.601151f, 0.399838f),
        make_mat3_rows(1.255528f, -0.076749f, -0.178779f, -0.078411f, 0.930809f, 0.147602f, 0.004733f, 0.691367f, 0.303900f),
    };
}

const std::array<glm::mat3, 11>& cvd_tables(const std::string& cvd_type)
{
    static const std::array<glm::mat3, 11> prot = protanomaly_tables();
    static const std::array<glm::mat3, 11> deut = deuteranomaly_tables();
    static const std::array<glm::mat3, 11> trit = tritanomaly_tables();

    const std::string key = to_lower(cvd_type);
    if (key == "protanomaly") {
        return prot;
    }
    if (key == "deuteranomaly") {
        return deut;
    }
    if (key == "tritanomaly") {
        return trit;
    }
    throw std::invalid_argument("unknown cvd_type: " + cvd_type);
}

} // namespace

Ciecam02Surround ciecam02SurroundAverage()
{
    return Ciecam02Surround {1.0f, 0.69f, 1.0f};
}

Ciecam02Surround ciecam02SurroundDim()
{
    return Ciecam02Surround {0.9f, 0.59f, 0.9f};
}

Ciecam02Surround ciecam02SurroundDark()
{
    return Ciecam02Surround {0.8f, 0.525f, 0.8f};
}

Ciecam02Space ciecam02SpaceSrgb()
{
    return Ciecam02Space {
        glm::vec3(95.047f, 100.0f, 108.883f),
        20.0f,
        (64.0f / glm::pi<float>()) / 5.0f,
        ciecam02SurroundAverage(),
    };
}

Ciecam02Correlates xyz100ToCiecam02(const glm::vec3& xyz100, const Ciecam02Space& space, const std::string& onNegativeA)
{
    const Ciecam02Precomputed p = precompute(space);
    const glm::vec3 RGB = M_CAT02 * xyz100;
    const glm::vec3 RGB_C = p.D_RGB * RGB;
    const glm::vec3 RGBprime = M_HPE_M_CAT02_inv * RGB_C;

    const glm::vec3 RGBprime_signs(sign_of(RGBprime.x), sign_of(RGBprime.y), sign_of(RGBprime.z));
    const glm::vec3 tmp = glm::pow((p.F_L * RGBprime_signs * RGBprime) / 100.0f, glm::vec3(0.42f));
    const glm::vec3 RGBprime_a = RGBprime_signs * 400.0f * (tmp / (tmp + 27.13f)) + 0.1f;

    const float a = glm::dot(glm::vec3(1.0f, -12.0f / 11.0f, 1.0f / 11.0f), RGBprime_a);
    const float b = glm::dot(glm::vec3(1.0f / 9.0f, 1.0f / 9.0f, -2.0f / 9.0f), RGBprime_a);
    const float h_rad = std::atan2(b, a);
    const float h = mod_360(glm::degrees(h_rad));
    const float H = ciecam_h_to_H(h);

    float A = (glm::dot(glm::vec3(2.0f, 1.0f, 1.0f / 20.0f), RGBprime_a) - 0.305f) * p.N_bb;
    const std::string mode = to_lower(onNegativeA);
    if (A < 0.0f && mode == "raise") {
        throw std::invalid_argument("achromatic signal A is negative in XYZ100_to_CIECAM02");
    }
    if (A < 0.0f && mode == "nan") {
        A = std::numeric_limits<float>::quiet_NaN();
    }
    if (mode != "raise" && mode != "nan") {
        throw std::invalid_argument("onNegativeA must be 'raise' or 'nan'");
    }

    const float J = 100.0f * std::pow(A / p.A_w, space.surround.c * p.z);
    const float Q = ((4.0f / space.surround.c) * std::sqrt(J / 100.0f)
                     * (p.A_w + 4.0f) * std::pow(p.F_L, 0.25f));

    const float e = (12500.0f / 13.0f) * space.surround.N_c * p.N_cb * (std::cos(h_rad + 2.0f) + 3.8f);
    const float t = (e * std::sqrt(a * a + b * b))
                    / glm::dot(glm::vec3(1.0f, 1.0f, 21.0f / 20.0f), RGBprime_a);

    const float C = std::pow(t, 0.9f) * std::sqrt(J / 100.0f) * std::pow(1.64f - std::pow(0.29f, p.n), 0.73f);
    const float M = C * std::pow(p.F_L, 0.25f);
    const float s = 100.0f * std::sqrt(M / Q);

    return Ciecam02Correlates {J, C, h, Q, M, s, H};
}

glm::vec3 ciecam02ToXyz100(const Ciecam02Space& space, const std::map<std::string, float>& correlates)
{
    std::map<std::string, float> lowered;
    for (const auto& [key, value] : correlates) {
        lowered[to_lower(key)] = value;
    }

    require_exactly_one(lowered, "j", "q");
    require_exactly_one(lowered, "c", "m", "s");

    // Re-read from original keys to preserve H distinction.
    bool has_small_h = false;
    bool has_big_H = false;
    float h = 0.0f;
    float H = 0.0f;
    for (const auto& [key, value] : correlates) {
        if (key == "h") {
            has_small_h = true;
            h = value;
        }
        if (key == "H") {
            has_big_H = true;
            H = value;
        }
    }

    // Also accept lower-case-only normalized input for H-like values.
    if (!has_small_h && !has_big_H && lowered.find("h") != lowered.end()) {
        has_small_h = true;
        h = lowered.at("h");
    }

    if ((has_small_h ? 1 : 0) + (has_big_H ? 1 : 0) != 1) {
        throw std::invalid_argument("exactly one of h or H is required");
    }

    const Ciecam02Precomputed p = precompute(space);

    const bool has_j = lowered.find("j") != lowered.end();
    const bool has_q = lowered.find("q") != lowered.end();
    const bool has_c = lowered.find("c") != lowered.end();
    const bool has_m = lowered.find("m") != lowered.end();
    const bool has_s = lowered.find("s") != lowered.end();

    float J = has_j ? lowered.at("j") : 0.0f;
    float Q = has_q ? lowered.at("q") : 0.0f;
    float C = has_c ? lowered.at("c") : 0.0f;
    float M = has_m ? lowered.at("m") : 0.0f;
    float s = has_s ? lowered.at("s") : 0.0f;

    if (!has_j) {
        J = 6.25f * std::pow((space.surround.c * Q) / ((p.A_w + 4.0f) * std::pow(p.F_L, 0.25f)), 2.0f);
    }

    if (!has_c) {
        if (has_m) {
            C = M / std::pow(p.F_L, 0.25f);
        } else {
            if (!has_q) {
                Q = ((4.0f / space.surround.c) * std::sqrt(J / 100.0f)
                     * (p.A_w + 4.0f) * std::pow(p.F_L, 0.25f));
            }
            C = std::pow(s / 100.0f, 2.0f) * (Q / std::pow(p.F_L, 0.25f));
        }
    }

    if (!has_small_h) {
        h = ciecam_H_to_h(H);
    }

    const float t = std::pow(C / (std::sqrt(J / 100.0f) * std::pow(1.64f - std::pow(0.29f, p.n), 0.73f)), 1.0f / 0.9f);
    const float e_t = 0.25f * (std::cos(glm::radians(h) + 2.0f) + 3.8f);
    const float A = p.A_w * std::pow(J / 100.0f, 1.0f / (space.surround.c * p.z));

    const float one_over_t = (t == 0.0f) ? std::numeric_limits<float>::infinity() : (1.0f / t);
    const float p_1 = (50000.0f / 13.0f) * space.surround.N_c * p.N_cb * e_t * one_over_t;
    const float p_2 = A / p.N_bb + 0.305f;
    const float p_3 = 21.0f / 20.0f;

    const float sin_h = std::sin(glm::radians(h));
    const float cos_h = std::cos(glm::radians(h));

    const float num = p_2 * (2.0f + p_3) * (460.0f / 1403.0f);
    const float denom_part2 = (2.0f + p_3) * (220.0f / 1403.0f);
    const float denom_part3 = (-27.0f / 1403.0f) + p_3 * (6300.0f / 1403.0f);

    float a = 0.0f;
    float b = 0.0f;
    if (std::abs(sin_h) >= std::abs(cos_h)) {
        b = num / (p_1 / sin_h + (denom_part2 * cos_h / sin_h) + denom_part3);
        a = b * cos_h / sin_h;
    } else {
        a = num / (p_1 / cos_h + denom_part2 + (denom_part3 * sin_h / cos_h));
        b = a * sin_h / cos_h;
    }

    const glm::mat3 RGBprime_a_matrix = (1.0f / 1403.0f)
                                         * make_mat3_rows(460.0f, 451.0f, 288.0f,
                                                          460.0f, -891.0f, -261.0f,
                                                          460.0f, -220.0f, -6300.0f);

    const glm::vec3 p2ab(p_2, a, b);
    const glm::vec3 RGBprime_a = RGBprime_a_matrix * p2ab;

    const glm::vec3 delta = RGBprime_a - 0.1f;
    const glm::vec3 abs_delta(std::abs(delta.x), std::abs(delta.y), std::abs(delta.z));
    const glm::vec3 signed_delta(sign_of(delta.x), sign_of(delta.y), sign_of(delta.z));

    const glm::vec3 ratio = (27.13f * abs_delta) / (400.0f - abs_delta);
    const glm::vec3 RGBprime = signed_delta * (100.0f / p.F_L) * glm::pow(ratio, glm::vec3(1.0f / 0.42f));

    const glm::vec3 RGB_C = M_CAT02_M_HPE_inv * RGBprime;
    const glm::vec3 RGB = RGB_C / p.D_RGB;
    return M_CAT02_inv * RGB;
}

glm::mat3 machadoEtAl2009Matrix(const std::string& cvdType, float severity)
{
    if (severity < 0.0f || severity > 100.0f) {
        throw std::invalid_argument("severity must be between 0 and 100");
    }
    const auto& tables = cvd_tables(cvdType);
    const float fraction = std::fmod(severity, 10.0f);
    const int low = static_cast<int>(std::floor(severity / 10.0f)) * 10;
    if (severity == 100.0f) {
        return tables[10];
    }
    const int high = low + 10;

    const glm::mat3 low_m = tables[low / 10];
    const glm::mat3 high_m = tables[high / 10];
    const float t = fraction / 10.0f;
    return (1.0f - t) * low_m + t * high_m;
}

glm::vec3 applyMatrix3x3(const glm::mat3& matrix, const glm::vec3& value)
{
    return matrix * value;
}

glm::vec3 jmhToJab(const glm::vec3& jmh, const LuoEtAl2006UniformSpace& space)
{
    const float J = jmh.x;
    const float M = jmh.y;
    const float h = jmh.z;

    float Jp = (1.0f + 100.0f * space.c1) * J / (1.0f + space.c1 * J);
    Jp /= space.KL;
    const float Mp = (1.0f / space.c2) * std::log(1.0f + space.c2 * M);

    const float h_rad = glm::radians(h);
    const float ap = Mp * std::cos(h_rad);
    const float bp = Mp * std::sin(h_rad);
    return glm::vec3(Jp, ap, bp);
}

glm::vec3 jabToJmh(const glm::vec3& jab, const LuoEtAl2006UniformSpace& space)
{
    float Jp = jab.x * space.KL;
    const float ap = jab.y;
    const float bp = jab.z;

    const float J = -Jp / (space.c1 * Jp - 100.0f * space.c1 - 1.0f);
    const float Mp = std::hypot(ap, bp);
    const float h = mod_360(glm::degrees(std::atan2(bp, ap)));
    const float M = (std::exp(space.c2 * Mp) - 1.0f) / space.c2;
    return glm::vec3(J, M, h);
}

LuoEtAl2006UniformSpace cam02UcsSpace()
{
    return LuoEtAl2006UniformSpace {1.0f, 0.007f, 0.0228f};
}

LuoEtAl2006UniformSpace cam02LcdSpace()
{
    return LuoEtAl2006UniformSpace {0.77f, 0.007f, 0.0053f};
}

LuoEtAl2006UniformSpace cam02ScdSpace()
{
    return LuoEtAl2006UniformSpace {1.24f, 0.007f, 0.0363f};
}
