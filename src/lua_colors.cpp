#include <map>
#include <sol/sol.hpp>
#include <string>
#include <vector>

#include <glm/glm.hpp>

#include "colors.h"

namespace {

sol::table swatch_to_table(sol::state_view lua, const std::map<int, glm::vec3>& swatch)
{
    sol::table tbl = lua.create_table();
    for (const auto& [key, value] : swatch) {
        tbl[key] = value;
    }
    return tbl;
}

sol::table colors_create_color_swatch(sol::this_state ts, const glm::vec3& base_color)
{
    sol::state_view lua(ts);
    return swatch_to_table(lua, createColorSwatch(base_color));
}

sol::table colors_create_color_swatch(sol::this_state ts, const glm::vec4& base_color)
{
    sol::state_view lua(ts);
    return swatch_to_table(lua, createColorSwatch(glm::vec3(base_color)));
}

glm::vec3 colors_adapt_xyz(const glm::vec3& xyz, const std::string& source_illuminant, const std::string& target_illuminant)
{
    return adaptXyz(xyz, source_illuminant, target_illuminant, "2", "bradford");
}

glm::vec3 colors_adapt_xyz_observer(const glm::vec3& xyz, const std::string& source_illuminant,
                                    const std::string& target_illuminant, const std::string& observer)
{
    return adaptXyz(xyz, source_illuminant, target_illuminant, observer, "bradford");
}

glm::vec3 colors_adapt_xyz_full(const glm::vec3& xyz, const std::string& source_illuminant,
                                const std::string& target_illuminant, const std::string& observer,
                                const std::string& adaptation)
{
    return adaptXyz(xyz, source_illuminant, target_illuminant, observer, adaptation);
}

float colors_delta_e_cie1994(const glm::vec3& lab1, const glm::vec3& lab2)
{
    return deltaECie1994(lab1, lab2);
}

float colors_delta_e_cie2000(const glm::vec3& lab1, const glm::vec3& lab2)
{
    return deltaECie2000(lab1, lab2);
}

float colors_delta_e_cmc(const glm::vec3& lab1, const glm::vec3& lab2)
{
    return deltaECmc(lab1, lab2);
}

std::vector<float> table_to_float_vector(const sol::table& tbl)
{
    std::vector<float> out;
    const size_t n = tbl.size();
    out.reserve(n);
    for (size_t i = 1; i <= n; ++i) {
        out.push_back(tbl.get<float>(i));
    }
    return out;
}

std::vector<glm::vec3> table_to_vec3_vector(const sol::table& tbl)
{
    std::vector<glm::vec3> out;
    const size_t n = tbl.size();
    out.reserve(n);
    for (size_t i = 1; i <= n; ++i) {
        out.push_back(tbl.get<glm::vec3>(i));
    }
    return out;
}

sol::table float_vector_to_table(sol::this_state ts, const std::vector<float>& values)
{
    sol::state_view lua(ts);
    sol::table out = lua.create_table(values.size(), 0);
    for (size_t i = 0; i < values.size(); ++i) {
        out[i + 1] = values[i];
    }
    return out;
}

sol::table string_vector_to_table(sol::this_state ts, const std::vector<std::string>& values)
{
    sol::state_view lua(ts);
    sol::table out = lua.create_table(values.size(), 0);
    for (size_t i = 0; i < values.size(); ++i) {
        out[i + 1] = values[i];
    }
    return out;
}

glm::vec3 colors_xyz_to_lab(const glm::vec3& xyz)
{
    return xyzToLab(xyz, "2", "d65");
}

glm::vec3 colors_xyz_to_lab_full(const glm::vec3& xyz, const std::string& observer, const std::string& illuminant)
{
    return xyzToLab(xyz, observer, illuminant);
}

glm::vec3 colors_lab_to_xyz(const glm::vec3& lab)
{
    return labToXyz(lab, "2", "d65");
}

glm::vec3 colors_lab_to_xyz_full(const glm::vec3& lab, const std::string& observer, const std::string& illuminant)
{
    return labToXyz(lab, observer, illuminant);
}

glm::vec3 colors_xyz_to_luv(const glm::vec3& xyz)
{
    return xyzToLuv(xyz, "2", "d65");
}

glm::vec3 colors_xyz_to_luv_full(const glm::vec3& xyz, const std::string& observer, const std::string& illuminant)
{
    return xyzToLuv(xyz, observer, illuminant);
}

glm::vec3 colors_luv_to_xyz(const glm::vec3& luv)
{
    return luvToXyz(luv, "2", "d65");
}

glm::vec3 colors_luv_to_xyz_full(const glm::vec3& luv, const std::string& observer, const std::string& illuminant)
{
    return luvToXyz(luv, observer, illuminant);
}

sol::table colors_delta_e_cie1976_matrix(sol::this_state ts, const glm::vec3& lab, const sol::table& labs)
{
    return float_vector_to_table(ts, deltaECie1976Matrix(lab, table_to_vec3_vector(labs)));
}

sol::table colors_delta_e_cie1994_matrix(sol::this_state ts, const glm::vec3& lab, const sol::table& labs)
{
    return float_vector_to_table(ts, deltaECie1994Matrix(lab, table_to_vec3_vector(labs)));
}

sol::table colors_delta_e_cie2000_matrix(sol::this_state ts, const glm::vec3& lab, const sol::table& labs)
{
    return float_vector_to_table(ts, deltaECie2000Matrix(lab, table_to_vec3_vector(labs)));
}

sol::table colors_delta_e_cmc_matrix(sol::this_state ts, const glm::vec3& lab, const sol::table& labs)
{
    return float_vector_to_table(ts, deltaECmcMatrix(lab, table_to_vec3_vector(labs)));
}

glm::vec3 colors_spectral_to_xyz(const sol::table& spectral)
{
    return spectralToXyz(table_to_float_vector(spectral), "2", "d50");
}

glm::vec3 colors_spectral_to_xyz_observer(const sol::table& spectral, const std::string& observer)
{
    return spectralToXyz(table_to_float_vector(spectral), observer, "d50");
}

glm::vec3 colors_spectral_to_xyz_full(const sol::table& spectral, const std::string& observer, const std::string& illuminant)
{
    return spectralToXyz(table_to_float_vector(spectral), observer, illuminant);
}

float colors_ansi_density(const sol::table& spectral, const std::string& density_standard)
{
    return ansiDensity(table_to_float_vector(spectral), density_standard);
}

float colors_auto_density(const sol::table& spectral)
{
    return autoDensity(table_to_float_vector(spectral));
}

glm::vec4 colors_convert_color(const glm::vec4& value, const std::string& source_space, const std::string& target_space)
{
    return convertColor(value, source_space, target_space, "srgb", "d65", "d65", "2");
}

glm::vec4 colors_convert_color_rgb_space(const glm::vec4& value, const std::string& source_space,
                                         const std::string& target_space, const std::string& through_rgb_space)
{
    return convertColor(value, source_space, target_space, through_rgb_space, "d65", "d65", "2");
}

glm::vec4 colors_convert_color_full(const glm::vec4& value, const std::string& source_space,
                                    const std::string& target_space, const std::string& through_rgb_space,
                                    const std::string& source_illuminant, const std::string& target_illuminant,
                                    const std::string& observer)
{
    return convertColor(value, source_space, target_space, through_rgb_space, source_illuminant, target_illuminant, observer);
}

sol::table scalars_to_table(sol::this_state ts, const std::map<std::string, float>& values)
{
    sol::state_view lua(ts);
    sol::table t = lua.create_table();
    for (const auto& [key, value] : values) {
        t[key] = value;
    }
    return t;
}

sol::table colors_model_nayatani95(sol::this_state ts, float x, float y, float z, float x_n, float y_n, float z_n,
                                   float y_ob, float e_o, float e_or, float n)
{
    return scalars_to_table(ts, modelNayatani95(x, y, z, x_n, y_n, z_n, y_ob, e_o, e_or, n));
}

sol::table colors_model_hunt(sol::this_state ts, float x, float y, float z, float x_b, float y_b, float z_b, float x_w,
                             float y_w, float z_w, float l_a, float n_c, float n_b)
{
    return scalars_to_table(ts, modelHunt(x, y, z, x_b, y_b, z_b, x_w, y_w, z_w, l_a, n_c, n_b));
}

sol::table colors_model_rlab(sol::this_state ts, float x, float y, float z, float x_n, float y_n, float z_n,
                             float y_n_abs, float sigma, float d)
{
    return scalars_to_table(ts, modelRlab(x, y, z, x_n, y_n, z_n, y_n_abs, sigma, d));
}

sol::table colors_model_atd95(sol::this_state ts, float x, float y, float z, float x_0, float y_0, float z_0,
                              float y_0_abs, float k_1, float k_2, float sigma)
{
    return scalars_to_table(ts, modelAtd95(x, y, z, x_0, y_0, z_0, y_0_abs, k_1, k_2, sigma));
}

sol::table colors_model_llab(sol::this_state ts, float x, float y, float z, float x_0, float y_0, float z_0, float y_b,
                             float f_s, float f_l, float f_c, float l, float d)
{
    return scalars_to_table(ts, modelLlab(x, y, z, x_0, y_0, z_0, y_b, f_s, f_l, f_c, l, d));
}

sol::table colors_model_ciecam02(sol::this_state ts, float x, float y, float z, float x_w, float y_w, float z_w,
                                 float y_b, float l_a, float c, float n_c, float f, bool d)
{
    return scalars_to_table(ts, modelCiecam02(x, y, z, x_w, y_w, z_w, y_b, l_a, c, n_c, f, d));
}

sol::table colors_model_ciecam02m1(sol::this_state ts, float x, float y, float z, float x_w, float y_w, float z_w,
                                   float x_b, float y_b, float z_b, float l_a, float c, float n_c, float f, float p, bool d)
{
    return scalars_to_table(ts, modelCiecam02m1(x, y, z, x_w, y_w, z_w, x_b, y_b, z_b, l_a, c, n_c, f, p, d));
}

sol::table colors_conversion_path(sol::this_state ts, const std::string& source_space, const std::string& target_space)
{
    return string_vector_to_table(ts, getConversionPath(source_space, target_space));
}

} // namespace

namespace {

sol::table create_colors_table(sol::state_view lua)
{
    sol::table colors_table = lua.create_table();
    colors_table.set_function("create-color-swatch",
        sol::overload(
            static_cast<sol::table(*)(sol::this_state, const glm::vec3&)>(&colors_create_color_swatch),
            static_cast<sol::table(*)(sol::this_state, const glm::vec4&)>(&colors_create_color_swatch)
        )
    );
    colors_table.set_function("rgb-to-xyz", &rgbToXyz);
    colors_table.set_function("xyz-to-rgb", &xyzToRgb);
    colors_table.set_function(
        "xyz-to-lab",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&)>(&colors_xyz_to_lab),
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&)>(&colors_xyz_to_lab_full)));
    colors_table.set_function(
        "lab-to-xyz",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&)>(&colors_lab_to_xyz),
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&)>(&colors_lab_to_xyz_full)));
    colors_table.set_function("rgb-to-lab", &rgbToLab);
    colors_table.set_function("lab-to-rgb", &labToRgb);
    colors_table.set_function("lab-to-lchab", &labToLchab);
    colors_table.set_function("lchab-to-lab", &lchabToLab);
    colors_table.set_function(
        "xyz-to-luv",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&)>(&colors_xyz_to_luv),
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&)>(&colors_xyz_to_luv_full)));
    colors_table.set_function(
        "luv-to-xyz",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&)>(&colors_luv_to_xyz),
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&)>(&colors_luv_to_xyz_full)));
    colors_table.set_function("luv-to-lchuv", &luvToLchuv);
    colors_table.set_function("lchuv-to-luv", &lchuvToLuv);
    colors_table.set_function("xyz-to-xyy", &xyzToXyy);
    colors_table.set_function("xyy-to-xyz", &xyyToXyz);
    colors_table.set_function("rgb-to-hsv", &rgbToHsv);
    colors_table.set_function("hsv-to-rgb", &hsvToRgb);
    colors_table.set_function("rgb-to-hsl", &rgbToHsl);
    colors_table.set_function("hsl-to-rgb", &hslToRgb);
    colors_table.set_function("rgb-to-cmy", &rgbToCmy);
    colors_table.set_function("cmy-to-rgb", &cmyToRgb);
    colors_table.set_function("cmy-to-cmyk", &cmyToCmyk);
    colors_table.set_function("cmyk-to-cmy", &cmykToCmy);
    colors_table.set_function("xyz-to-ipt", &xyzToIpt);
    colors_table.set_function("ipt-to-xyz", &iptToXyz);
    colors_table.set_function("get-illuminant", &getIlluminant);
    colors_table.set_function(
        "adapt-xyz",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&)>(&colors_adapt_xyz),
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&, const std::string&)>(
                &colors_adapt_xyz_observer),
            static_cast<glm::vec3(*)(const glm::vec3&, const std::string&, const std::string&, const std::string&,
                                     const std::string&)>(&colors_adapt_xyz_full)));
    colors_table.set_function("delta-e-cie1976", &deltaECie1976);
    colors_table.set_function(
        "delta-e-cie1994",
        sol::overload(
            static_cast<float(*)(const glm::vec3&, const glm::vec3&)>(&colors_delta_e_cie1994),
            static_cast<float(*)(const glm::vec3&, const glm::vec3&, float, float, float, float, float)>(&deltaECie1994)));
    colors_table.set_function(
        "delta-e-cie2000",
        sol::overload(
            static_cast<float(*)(const glm::vec3&, const glm::vec3&)>(&colors_delta_e_cie2000),
            static_cast<float(*)(const glm::vec3&, const glm::vec3&, float, float, float)>(&deltaECie2000)));
    colors_table.set_function(
        "delta-e-cmc",
        sol::overload(
            static_cast<float(*)(const glm::vec3&, const glm::vec3&)>(&colors_delta_e_cmc),
            static_cast<float(*)(const glm::vec3&, const glm::vec3&, float, float)>(&deltaECmc)));
    colors_table.set_function("delta-e-cie1976-matrix", &colors_delta_e_cie1976_matrix);
    colors_table.set_function("delta-e-cie1994-matrix", &colors_delta_e_cie1994_matrix);
    colors_table.set_function("delta-e-cie2000-matrix", &colors_delta_e_cie2000_matrix);
    colors_table.set_function("delta-e-cmc-matrix", &colors_delta_e_cmc_matrix);
    colors_table.set_function(
        "spectral-to-xyz",
        sol::overload(
            static_cast<glm::vec3(*)(const sol::table&)>(&colors_spectral_to_xyz),
            static_cast<glm::vec3(*)(const sol::table&, const std::string&)>(&colors_spectral_to_xyz_observer),
            static_cast<glm::vec3(*)(const sol::table&, const std::string&, const std::string&)>(&colors_spectral_to_xyz_full)));
    colors_table.set_function("ansi-density", &colors_ansi_density);
    colors_table.set_function("auto-density", &colors_auto_density);
    colors_table.set_function(
        "convert-color",
        sol::overload(
            static_cast<glm::vec4(*)(const glm::vec4&, const std::string&, const std::string&)>(&colors_convert_color),
            static_cast<glm::vec4(*)(const glm::vec4&, const std::string&, const std::string&, const std::string&)>(
                &colors_convert_color_rgb_space),
            static_cast<glm::vec4(*)(const glm::vec4&, const std::string&, const std::string&, const std::string&,
                                     const std::string&, const std::string&, const std::string&)>(&colors_convert_color_full)));
    colors_table.set_function("model-nayatani95", &colors_model_nayatani95);
    colors_table.set_function("model-hunt", &colors_model_hunt);
    colors_table.set_function("model-rlab", &colors_model_rlab);
    colors_table.set_function("model-atd95", &colors_model_atd95);
    colors_table.set_function("model-llab", &colors_model_llab);
    colors_table.set_function("model-ciecam02", &colors_model_ciecam02);
    colors_table.set_function("model-ciecam02m1", &colors_model_ciecam02m1);
    colors_table.set_function("conversion-path", &colors_conversion_path);
    colors_table.set_function("can-convert", &canConvert);
    colors_table.set_function("rgb-to-upscaled", &rgbToUpscaled);
    colors_table.set_function("rgb-to-hex", &rgbToHex);
    colors_table.set_function("rgb-from-hex", &rgbFromHex);
    colors_table.set_function("clamp-rgb", &clampRgb);
    return colors_table;
}

} // namespace

void lua_bind_colors(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("colors", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_colors_table(lua);
    });
}
