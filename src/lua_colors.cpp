#include <algorithm>
#include <cctype>
#include <map>
#include <sol/sol.hpp>
#include <string>
#include <vector>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_inverse.hpp>

#include "colors.h"
#include "colorspacious.h"

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

std::string to_lower(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

sol::table mat3_to_table(sol::this_state ts, const glm::mat3& matrix)
{
    sol::state_view lua(ts);
    sol::table out = lua.create_table(3, 0);
    for (int row = 0; row < 3; ++row) {
        sol::table row_t = lua.create_table(3, 0);
        for (int col = 0; col < 3; ++col) {
            row_t[col + 1] = matrix[col][row];
        }
        out[row + 1] = row_t;
    }
    return out;
}

sol::table ciecam_space_to_table(sol::this_state ts, const Ciecam02Space& space)
{
    sol::state_view lua(ts);
    sol::table t = lua.create_table();
    t["XYZ100_w"] = space.XYZ100_w;
    t["Y_b"] = space.Y_b;
    t["L_A"] = space.L_A;
    t["F"] = space.surround.F;
    t["c"] = space.surround.c;
    t["N_c"] = space.surround.N_c;
    return t;
}

sol::table ciecam_correlates_to_table(sol::this_state ts, const Ciecam02Correlates& c)
{
    sol::state_view lua(ts);
    sol::table t = lua.create_table();
    t["J"] = c.J;
    t["C"] = c.C;
    t["h"] = c.h;
    t["Q"] = c.Q;
    t["M"] = c.M;
    t["s"] = c.s;
    t["H"] = c.H;
    return t;
}

glm::vec3 parse_whitepoint(const sol::object& value)
{
    if (value.is<std::string>()) {
        return getIlluminant("2", value.as<std::string>());
    }
    if (value.is<glm::vec3>()) {
        return value.as<glm::vec3>();
    }
    if (value.is<sol::table>()) {
        sol::table t = value.as<sol::table>();
        return glm::vec3(t.get_or(1, 0.0f), t.get_or(2, 0.0f), t.get_or(3, 0.0f));
    }
    throw std::invalid_argument("XYZ100_w must be illuminant name, vec3, or [x y z]");
}

Ciecam02Surround parse_surround(const sol::object& value)
{
    if (!value.valid() || value == sol::nil) {
        return ciecam02SurroundAverage();
    }
    if (value.is<std::string>()) {
        const std::string key = to_lower(value.as<std::string>());
        if (key == "average") {
            return ciecam02SurroundAverage();
        }
        if (key == "dim") {
            return ciecam02SurroundDim();
        }
        if (key == "dark") {
            return ciecam02SurroundDark();
        }
        throw std::invalid_argument("unknown surround: " + value.as<std::string>());
    }
    if (value.is<sol::table>()) {
        sol::table t = value.as<sol::table>();
        return Ciecam02Surround {
            t.get_or("F", 1.0f),
            t.get_or("c", 0.69f),
            t.get_or("N_c", 1.0f),
        };
    }
    throw std::invalid_argument("surround must be string or table");
}

Ciecam02Space parse_ciecam02_space(const sol::object& value)
{
    Ciecam02Space out = ciecam02SpaceSrgb();
    if (!value.valid() || value == sol::nil) {
        return out;
    }
    if (!value.is<sol::table>()) {
        throw std::invalid_argument("ciecam02 space must be a table");
    }
    sol::table t = value.as<sol::table>();
    sol::optional<sol::object> white = t["XYZ100_w"];
    if (white) {
        out.XYZ100_w = parse_whitepoint(*white);
    }
    out.Y_b = t.get_or("Y_b", out.Y_b);
    out.L_A = t.get_or("L_A", out.L_A);
    out.surround = parse_surround(t["surround"]);
    sol::optional<float> F = t["F"];
    if (F) {
        out.surround.F = *F;
    }
    sol::optional<float> c = t["c"];
    if (c) {
        out.surround.c = *c;
    }
    sol::optional<float> N_c = t["N_c"];
    if (N_c) {
        out.surround.N_c = *N_c;
    }
    return out;
}

LuoEtAl2006UniformSpace parse_luo_space(const sol::object& value)
{
    if (!value.valid() || value == sol::nil) {
        return cam02UcsSpace();
    }
    if (value.is<std::string>()) {
        const std::string key = to_lower(value.as<std::string>());
        if (key == "cam02-ucs" || key == "ucs") {
            return cam02UcsSpace();
        }
        if (key == "cam02-lcd" || key == "lcd") {
            return cam02LcdSpace();
        }
        if (key == "cam02-scd" || key == "scd") {
            return cam02ScdSpace();
        }
        throw std::invalid_argument("unknown LuoEtAl2006 space: " + value.as<std::string>());
    }
    if (value.is<sol::table>()) {
        sol::table t = value.as<sol::table>();
        return LuoEtAl2006UniformSpace {
            t.get_or("KL", 1.0f),
            t.get_or("c1", 0.007f),
            t.get_or("c2", 0.0228f),
        };
    }
    throw std::invalid_argument("LuoEtAl2006 space must be a string or table");
}

sol::table luo_space_to_table(sol::this_state ts, const LuoEtAl2006UniformSpace& space)
{
    sol::state_view lua(ts);
    sol::table t = lua.create_table();
    t["KL"] = space.KL;
    t["c1"] = space.c1;
    t["c2"] = space.c2;
    return t;
}

sol::table colors_ciecam02_space(sol::this_state ts)
{
    return ciecam_space_to_table(ts, ciecam02SpaceSrgb());
}

sol::table colors_ciecam02_space_opts(sol::this_state ts, const sol::table& options)
{
    return ciecam_space_to_table(ts, parse_ciecam02_space(options));
}

sol::table colors_xyz100_to_ciecam02(sol::this_state ts, const glm::vec3& xyz100)
{
    return ciecam_correlates_to_table(ts, xyz100ToCiecam02(xyz100, ciecam02SpaceSrgb(), "raise"));
}

sol::table colors_xyz100_to_ciecam02_space(sol::this_state ts, const glm::vec3& xyz100, const sol::table& space)
{
    return ciecam_correlates_to_table(ts, xyz100ToCiecam02(xyz100, parse_ciecam02_space(space), "raise"));
}

sol::table colors_xyz100_to_ciecam02_full(sol::this_state ts, const glm::vec3& xyz100, const sol::table& space,
                                          const std::string& on_negative_a)
{
    return ciecam_correlates_to_table(ts, xyz100ToCiecam02(xyz100, parse_ciecam02_space(space), on_negative_a));
}

glm::vec3 colors_ciecam02_to_xyz100(const sol::table& correlates)
{
    std::map<std::string, float> args;
    auto read_number = [&](const std::string& key, float& out) -> bool {
        sol::object value = correlates[key];
        if (value.valid() && !value.is<sol::nil_t>() && (value.is<float>() || value.is<double>() || value.is<int>())) {
            out = static_cast<float>(value.as<double>());
            return true;
        }
        return false;
    };

    float v = 0.0f;
    if (read_number("J", v) || read_number("j", v)) {
        args["J"] = v;
    } else if (read_number("Q", v) || read_number("q", v)) {
        args["Q"] = v;
    }
    if (read_number("C", v) || read_number("c", v)) {
        args["C"] = v;
    } else if (read_number("M", v) || read_number("m", v)) {
        args["M"] = v;
    } else if (read_number("s", v)) {
        args["s"] = v;
    }
    if (read_number("h", v)) {
        args["h"] = v;
    } else if (read_number("H", v)) {
        args["H"] = v;
    }
    return ciecam02ToXyz100(ciecam02SpaceSrgb(), args);
}

glm::vec3 colors_ciecam02_to_xyz100_space(const sol::table& correlates, const sol::table& space)
{
    std::map<std::string, float> args;
    auto read_number = [&](const std::string& key, float& out) -> bool {
        sol::object value = correlates[key];
        if (value.valid() && !value.is<sol::nil_t>() && (value.is<float>() || value.is<double>() || value.is<int>())) {
            out = static_cast<float>(value.as<double>());
            return true;
        }
        return false;
    };

    float v = 0.0f;
    if (read_number("J", v) || read_number("j", v)) {
        args["J"] = v;
    } else if (read_number("Q", v) || read_number("q", v)) {
        args["Q"] = v;
    }
    if (read_number("C", v) || read_number("c", v)) {
        args["C"] = v;
    } else if (read_number("M", v) || read_number("m", v)) {
        args["M"] = v;
    } else if (read_number("s", v)) {
        args["s"] = v;
    }
    if (read_number("h", v)) {
        args["h"] = v;
    } else if (read_number("H", v)) {
        args["H"] = v;
    }
    return ciecam02ToXyz100(parse_ciecam02_space(space), args);
}

sol::table colors_machado_matrix(sol::this_state ts, const std::string& cvd_type, float severity)
{
    return mat3_to_table(ts, machadoEtAl2009Matrix(cvd_type, severity));
}

glm::vec3 colors_cvd_forward(const glm::vec3& rgb, const std::string& cvd_type, float severity)
{
    return applyMatrix3x3(machadoEtAl2009Matrix(cvd_type, severity), rgb);
}

glm::vec3 colors_cvd_inverse(const glm::vec3& rgb, const std::string& cvd_type, float severity)
{
    const glm::mat3 fwd = machadoEtAl2009Matrix(cvd_type, severity);
    return applyMatrix3x3(glm::inverse(fwd), rgb);
}

sol::table colors_cam02_space(sol::this_state ts, const std::string& name)
{
    const std::string key = to_lower(name);
    if (key == "cam02-ucs" || key == "ucs") {
        return luo_space_to_table(ts, cam02UcsSpace());
    }
    if (key == "cam02-lcd" || key == "lcd") {
        return luo_space_to_table(ts, cam02LcdSpace());
    }
    if (key == "cam02-scd" || key == "scd") {
        return luo_space_to_table(ts, cam02ScdSpace());
    }
    throw std::invalid_argument("unknown CAM02 space name: " + name);
}

glm::vec3 colors_jmh_to_jab(const glm::vec3& jmh)
{
    return jmhToJab(jmh, cam02UcsSpace());
}

glm::vec3 colors_jmh_to_jab_space(const glm::vec3& jmh, const sol::object& space)
{
    return jmhToJab(jmh, parse_luo_space(space));
}

glm::vec3 colors_jab_to_jmh(const glm::vec3& jab)
{
    return jabToJmh(jab, cam02UcsSpace());
}

glm::vec3 colors_jab_to_jmh_space(const glm::vec3& jab, const sol::object& space)
{
    return jabToJmh(jab, parse_luo_space(space));
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
    colors_table.set_function(
        "ciecam02-space",
        sol::overload(
            static_cast<sol::table(*)(sol::this_state)>(&colors_ciecam02_space),
            static_cast<sol::table(*)(sol::this_state, const sol::table&)>(&colors_ciecam02_space_opts)));
    colors_table.set_function(
        "xyz100-to-ciecam02",
        sol::overload(
            static_cast<sol::table(*)(sol::this_state, const glm::vec3&)>(&colors_xyz100_to_ciecam02),
            static_cast<sol::table(*)(sol::this_state, const glm::vec3&, const sol::table&)>(&colors_xyz100_to_ciecam02_space),
            static_cast<sol::table(*)(sol::this_state, const glm::vec3&, const sol::table&, const std::string&)>(
                &colors_xyz100_to_ciecam02_full)));
    colors_table.set_function(
        "ciecam02-to-xyz100",
        sol::overload(
            static_cast<glm::vec3(*)(const sol::table&)>(&colors_ciecam02_to_xyz100),
            static_cast<glm::vec3(*)(const sol::table&, const sol::table&)>(&colors_ciecam02_to_xyz100_space)));
    colors_table.set_function("machado-et-al-2009-matrix", &colors_machado_matrix);
    colors_table.set_function("cvd-forward", &colors_cvd_forward);
    colors_table.set_function("cvd-inverse", &colors_cvd_inverse);
    colors_table.set_function("cam02-space", &colors_cam02_space);
    colors_table.set_function(
        "jmh-to-jab",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&)>(&colors_jmh_to_jab),
            static_cast<glm::vec3(*)(const glm::vec3&, const sol::object&)>(&colors_jmh_to_jab_space)));
    colors_table.set_function(
        "jab-to-jmh",
        sol::overload(
            static_cast<glm::vec3(*)(const glm::vec3&)>(&colors_jab_to_jmh),
            static_cast<glm::vec3(*)(const glm::vec3&, const sol::object&)>(&colors_jab_to_jmh_space)));
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
