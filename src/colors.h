#pragma once

#include <glm/glm.hpp>
#include <map>
#include <string>
#include <vector>

std::map<int, glm::vec3> createColorSwatch(const glm::vec3& baseColor);

glm::vec3 rgbToXyz(const glm::vec3& rgb);
glm::vec3 xyzToRgb(const glm::vec3& xyz);
glm::vec3 xyzToLab(const glm::vec3& xyz);
glm::vec3 labToXyz(const glm::vec3& lab);
glm::vec3 xyzToLab(const glm::vec3& xyz, const std::string& observer, const std::string& illuminant);
glm::vec3 labToXyz(const glm::vec3& lab, const std::string& observer, const std::string& illuminant);
glm::vec3 rgbToLab(const glm::vec3& rgb);
glm::vec3 labToRgb(const glm::vec3& lab);

glm::vec3 labToLchab(const glm::vec3& lab);
glm::vec3 lchabToLab(const glm::vec3& lchab);
glm::vec3 xyzToLuv(const glm::vec3& xyz);
glm::vec3 luvToXyz(const glm::vec3& luv);
glm::vec3 xyzToLuv(const glm::vec3& xyz, const std::string& observer, const std::string& illuminant);
glm::vec3 luvToXyz(const glm::vec3& luv, const std::string& observer, const std::string& illuminant);
glm::vec3 luvToLchuv(const glm::vec3& luv);
glm::vec3 lchuvToLuv(const glm::vec3& lchuv);
glm::vec3 xyzToXyy(const glm::vec3& xyz);
glm::vec3 xyyToXyz(const glm::vec3& xyy);

glm::vec3 rgbToHsv(const glm::vec3& rgb);
glm::vec3 hsvToRgb(const glm::vec3& hsv);
glm::vec3 rgbToHsl(const glm::vec3& rgb);
glm::vec3 hslToRgb(const glm::vec3& hsl);
glm::vec3 rgbToCmy(const glm::vec3& rgb);
glm::vec3 cmyToRgb(const glm::vec3& cmy);
glm::vec4 cmyToCmyk(const glm::vec3& cmy);
glm::vec3 cmykToCmy(const glm::vec4& cmyk);

glm::vec3 xyzToIpt(const glm::vec3& xyz);
glm::vec3 iptToXyz(const glm::vec3& ipt);

glm::vec3 getIlluminant(const std::string& observer, const std::string& illuminant);
glm::vec3 adaptXyz(const glm::vec3& xyz,
                   const std::string& sourceIlluminant,
                   const std::string& targetIlluminant,
                   const std::string& observer = "2",
                   const std::string& adaptation = "bradford");

float deltaECie1976(const glm::vec3& lab1, const glm::vec3& lab2);
float deltaECie1994(const glm::vec3& lab1, const glm::vec3& lab2, float K_L = 1.0f, float K_C = 1.0f,
                    float K_H = 1.0f, float K_1 = 0.045f, float K_2 = 0.015f);
float deltaECie2000(const glm::vec3& lab1, const glm::vec3& lab2, float K_l = 1.0f, float K_c = 1.0f,
                    float K_h = 1.0f);
float deltaECmc(const glm::vec3& lab1, const glm::vec3& lab2, float p_l = 2.0f, float p_c = 1.0f);

std::vector<float> deltaECie1976Matrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs);
std::vector<float> deltaECie1994Matrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs, float K_L = 1.0f,
                                       float K_C = 1.0f, float K_H = 1.0f, float K_1 = 0.045f,
                                       float K_2 = 0.015f);
std::vector<float> deltaECie2000Matrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs, float K_l = 1.0f,
                                       float K_c = 1.0f, float K_h = 1.0f);
std::vector<float> deltaECmcMatrix(const glm::vec3& lab, const std::vector<glm::vec3>& labs, float p_l = 2.0f,
                                   float p_c = 1.0f);

glm::vec3 spectralToXyz(const std::vector<float>& spectral, const std::string& observer = "2",
                        const std::string& illuminant = "d50");
float ansiDensity(const std::vector<float>& spectral, const std::string& densityStandard);
float autoDensity(const std::vector<float>& spectral);

glm::vec4 convertColor(const glm::vec4& value, const std::string& sourceSpace, const std::string& targetSpace,
                       const std::string& throughRgbSpace = "srgb", const std::string& sourceIlluminant = "d65",
                       const std::string& targetIlluminant = "d65", const std::string& observer = "2");
std::vector<std::string> getConversionPath(const std::string& sourceSpace, const std::string& targetSpace);
bool canConvert(const std::string& sourceSpace, const std::string& targetSpace);

glm::vec3 rgbToUpscaled(const glm::vec3& rgb);
std::string rgbToHex(const glm::vec3& rgb);
glm::vec3 rgbFromHex(const std::string& hex);
glm::vec3 clampRgb(const glm::vec3& rgb);

std::map<std::string, float> modelNayatani95(float x, float y, float z, float x_n, float y_n, float z_n, float y_ob,
                                             float e_o, float e_or, float n = 1.0f);
std::map<std::string, float> modelHunt(float x, float y, float z, float x_b, float y_b, float z_b, float x_w, float y_w,
                                       float z_w, float l_a, float n_c, float n_b);
std::map<std::string, float> modelRlab(float x, float y, float z, float x_n, float y_n, float z_n, float y_n_abs,
                                       float sigma, float d);
std::map<std::string, float> modelAtd95(float x, float y, float z, float x_0, float y_0, float z_0, float y_0_abs,
                                        float k_1, float k_2, float sigma = 300.0f);
std::map<std::string, float> modelLlab(float x, float y, float z, float x_0, float y_0, float z_0, float y_b, float f_s,
                                       float f_l, float f_c, float l, float d = 1.0f);
std::map<std::string, float> modelCiecam02(float x, float y, float z, float x_w, float y_w, float z_w, float y_b,
                                           float l_a, float c, float n_c, float f, bool d = false);
std::map<std::string, float> modelCiecam02m1(float x, float y, float z, float x_w, float y_w, float z_w, float x_b,
                                             float y_b, float z_b, float l_a, float c, float n_c, float f, float p,
                                             bool d = false);
