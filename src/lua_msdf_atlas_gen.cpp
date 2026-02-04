#include <sol/sol.hpp>

#include <msdf-atlas-gen/msdf-atlas-gen.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

constexpr double kDefaultEmSize = 32.0;
constexpr double kDefaultPxRange = 2.0;
constexpr double kDefaultAngleThreshold = 3.0;
constexpr double kDefaultMiterLimit = 1.0;

struct FontContext {
    msdfgen::FreetypeHandle* freetype = nullptr;
    msdfgen::FontHandle* font = nullptr;

    FontContext() { freetype = msdfgen::initializeFreetype(); }

    ~FontContext()
    {
        if (font) {
            msdfgen::destroyFont(font);
            font = nullptr;
        }
        if (freetype) {
            msdfgen::deinitializeFreetype(freetype);
            freetype = nullptr;
        }
    }

    FontContext(const FontContext&) = delete;
    FontContext& operator=(const FontContext&) = delete;

    void load_font(const std::string& path)
    {
        if (!std::filesystem::exists(path)) {
            throw std::runtime_error("msdf-atlas-gen: font file not found: " + path);
        }
        if (!std::filesystem::is_regular_file(path)) {
            throw std::runtime_error("msdf-atlas-gen: font path is not a file: " + path);
        }
        if (!freetype) {
            throw std::runtime_error("msdf-atlas-gen: freetype initialization failed");
        }
        font = msdfgen::loadFont(freetype, path.c_str());
        if (!font) {
            throw std::runtime_error("msdf-atlas-gen: failed to load font: " + path);
        }
    }
};

#ifndef MSDFGEN_DISABLE_VARIABLE_FONTS
msdfgen::FontHandle* load_var_font(msdfgen::FreetypeHandle* library, const std::string& spec)
{
    std::string buffer;
    const char* filename = spec.c_str();
    while (*filename && *filename != '?') {
        buffer.push_back(*filename++);
    }
    msdfgen::FontHandle* font = msdfgen::loadFont(library, buffer.c_str());
    if (font && *filename++ == '?') {
        do {
            buffer.clear();
            while (*filename && *filename != '=') {
                buffer.push_back(*filename++);
            }
            if (*filename == '=') {
                double value = 0;
                int skip = 0;
                if (sscanf(++filename, "%lf%n", &value, &skip) == 1) {
                    msdfgen::setFontVariationAxis(library, font, buffer.c_str(), value);
                    filename += skip;
                }
            }
        } while (*filename++ == '&');
    }
    return font;
}
#endif

struct FontInputSpec {
    std::string font_filename;
    bool variable_font = false;
    msdf_atlas::GlyphIdentifierType glyph_identifier_type = msdf_atlas::GlyphIdentifierType::UNICODE_CODEPOINT;
    std::string charset_filename;
    std::string charset_string;
    double font_scale = -1.0;
    std::string font_name;
    bool all_glyphs = false;
};

struct MsdfAtlasConfig {
    msdf_atlas::ImageType image_type = msdf_atlas::ImageType::MSDF;
    msdf_atlas::ImageFormat image_format = msdf_atlas::ImageFormat::UNSPECIFIED;
    msdfgen::YAxisOrientation y_direction = msdfgen::Y_UPWARD;
    int width = -1;
    int height = -1;
    double em_size = 0.0;
    msdfgen::Range px_range = 0.0;
    double angle_threshold = kDefaultAngleThreshold;
    double miter_limit = kDefaultMiterLimit;
    bool px_align_origin_x = false;
    bool px_align_origin_y = true;
    struct {
        int cell_width = -1;
        int cell_height = -1;
        int cols = 0;
        int rows = 0;
        bool fixed_origin_x = false;
        bool fixed_origin_y = true;
    } grid;
    void (*edge_coloring)(msdfgen::Shape&, double, unsigned long long) = msdfgen::edgeColoringInkTrap;
    bool expensive_coloring = false;
    unsigned long long coloring_seed = 0;
    msdf_atlas::GeneratorAttributes generator_attributes = {};
    bool preprocess_geometry = false;
    bool kerning = true;
    int thread_count = 0;
    std::string artery_font_filename;
    std::string image_filename;
    std::string json_filename;
    std::string csv_filename;
    std::string shadron_preview_filename;
    std::string shadron_preview_text;
};

struct MsdfAtlasRequest {
    std::vector<FontInputSpec> fonts;
    MsdfAtlasConfig config;
    msdf_atlas::PackingStyle packing_style = msdf_atlas::PackingStyle::TIGHT;
    msdf_atlas::DimensionsConstraint atlas_constraint = msdf_atlas::DimensionsConstraint::NONE;
    msdf_atlas::DimensionsConstraint cell_constraint = msdf_atlas::DimensionsConstraint::NONE;
    int fixed_cell_width = -1;
    int fixed_cell_height = -1;
    double min_em_size = 0.0;
    msdfgen::Range range_value = 0.0;
    bool range_value_set = false;
    bool range_units_em = false;
    msdf_atlas::Padding inner_padding;
    msdf_atlas::Padding outer_padding;
    bool inner_padding_em = true;
    bool outer_padding_em = true;
    bool explicit_overlap = false;
    bool explicit_scanline = false;
    bool explicit_error_correction = false;
};

msdf_atlas::ImageType parse_image_type(const std::string& value)
{
    if (value == "hardmask") {
        return msdf_atlas::ImageType::HARD_MASK;
    }
    if (value == "softmask") {
        return msdf_atlas::ImageType::SOFT_MASK;
    }
    if (value == "sdf") {
        return msdf_atlas::ImageType::SDF;
    }
    if (value == "psdf") {
        return msdf_atlas::ImageType::PSDF;
    }
    if (value == "msdf") {
        return msdf_atlas::ImageType::MSDF;
    }
    if (value == "mtsdf") {
        return msdf_atlas::ImageType::MTSDF;
    }
    throw std::runtime_error("msdf-atlas-gen: unknown image type: " + value);
}

msdf_atlas::ImageFormat parse_image_format(const std::string& value)
{
    if (value == "png") {
        return msdf_atlas::ImageFormat::PNG;
    }
    if (value == "bmp") {
        return msdf_atlas::ImageFormat::BMP;
    }
    if (value == "tiff") {
        return msdf_atlas::ImageFormat::TIFF;
    }
    if (value == "rgba") {
        return msdf_atlas::ImageFormat::RGBA;
    }
    if (value == "fl32") {
        return msdf_atlas::ImageFormat::FL32;
    }
    if (value == "text") {
        return msdf_atlas::ImageFormat::TEXT;
    }
    if (value == "textfloat") {
        return msdf_atlas::ImageFormat::TEXT_FLOAT;
    }
    if (value == "bin") {
        return msdf_atlas::ImageFormat::BINARY;
    }
    if (value == "binfloat") {
        return msdf_atlas::ImageFormat::BINARY_FLOAT;
    }
    if (value == "binfloatbe") {
        return msdf_atlas::ImageFormat::BINARY_FLOAT_BE;
    }
    throw std::runtime_error("msdf-atlas-gen: unknown image format: " + value);
}

msdf_atlas::DimensionsConstraint parse_dimensions_constraint(const std::string& value)
{
    if (value == "none") {
        return msdf_atlas::DimensionsConstraint::NONE;
    }
    if (value == "square") {
        return msdf_atlas::DimensionsConstraint::SQUARE;
    }
    if (value == "square2") {
        return msdf_atlas::DimensionsConstraint::EVEN_SQUARE;
    }
    if (value == "square4") {
        return msdf_atlas::DimensionsConstraint::MULTIPLE_OF_FOUR_SQUARE;
    }
    if (value == "potr") {
        return msdf_atlas::DimensionsConstraint::POWER_OF_TWO_RECTANGLE;
    }
    if (value == "pots") {
        return msdf_atlas::DimensionsConstraint::POWER_OF_TWO_SQUARE;
    }
    throw std::runtime_error("msdf-atlas-gen: unknown size constraint: " + value);
}

msdfgen::YAxisOrientation parse_yorigin(const std::string& value)
{
    if (value == "bottom") {
        return msdfgen::Y_UPWARD;
    }
    if (value == "top") {
        return msdfgen::Y_DOWNWARD;
    }
    throw std::runtime_error("msdf-atlas-gen: unknown y-origin: " + value);
}

void parse_origin_flags(const std::string& value, bool& x, bool& y, const std::string& label)
{
    if (value == "off") {
        x = false;
        y = false;
        return;
    }
    if (value == "on") {
        x = true;
        y = true;
        return;
    }
    if (value == "horizontal") {
        x = true;
        y = false;
        return;
    }
    if (value == "vertical" || value == "baseline" || value == "default") {
        x = false;
        y = true;
        return;
    }
    throw std::runtime_error("msdf-atlas-gen: unknown " + label + " setting: " + value);
}

msdf_atlas::Padding parse_padding(const sol::object& obj, const std::string& label)
{
    if (obj.is<double>()) {
        double value = obj.as<double>();
        return msdf_atlas::Padding(value);
    }
    if (!obj.is<sol::table>()) {
        throw std::runtime_error("msdf-atlas-gen: " + label + " expects a number or table");
    }
    sol::table tbl = obj.as<sol::table>();
    sol::optional<double> l = tbl[1];
    sol::optional<double> b = tbl[2];
    sol::optional<double> r = tbl[3];
    sol::optional<double> t = tbl[4];
    if (!l || !b || !r || !t) {
        l = tbl["left"];
        b = tbl["bottom"];
        r = tbl["right"];
        t = tbl["top"];
    }
    if (!l || !b || !r || !t) {
        throw std::runtime_error("msdf-atlas-gen: " + label + " requires four values");
    }
    msdf_atlas::Padding padding;
    padding.l = *l;
    padding.b = *b;
    padding.r = *r;
    padding.t = *t;
    return padding;
}

void apply_error_correction(const std::string& value, msdf_atlas::GeneratorAttributes& attributes, bool& explicit_mode)
{
    msdfgen::ErrorCorrectionConfig& ec = attributes.config.errorCorrection;
    if (value == "disabled" || value == "none") {
        ec.mode = msdfgen::ErrorCorrectionConfig::DISABLED;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE;
    } else if (value == "default" || value == "auto" || value == "auto-mixed" || value == "mixed") {
        ec.mode = msdfgen::ErrorCorrectionConfig::EDGE_PRIORITY;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::CHECK_DISTANCE_AT_EDGE;
    } else if (value == "auto-fast" || value == "fast") {
        ec.mode = msdfgen::ErrorCorrectionConfig::EDGE_PRIORITY;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE;
    } else if (value == "auto-full" || value == "full") {
        ec.mode = msdfgen::ErrorCorrectionConfig::EDGE_PRIORITY;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::ALWAYS_CHECK_DISTANCE;
    } else if (value == "distance" || value == "distance-fast" || value == "indiscriminate" || value == "indiscriminate-fast") {
        ec.mode = msdfgen::ErrorCorrectionConfig::INDISCRIMINATE;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE;
    } else if (value == "distance-full" || value == "indiscriminate-full") {
        ec.mode = msdfgen::ErrorCorrectionConfig::INDISCRIMINATE;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::ALWAYS_CHECK_DISTANCE;
    } else if (value == "edge-fast") {
        ec.mode = msdfgen::ErrorCorrectionConfig::EDGE_ONLY;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE;
    } else if (value == "edge" || value == "edge-full") {
        ec.mode = msdfgen::ErrorCorrectionConfig::EDGE_ONLY;
        ec.distanceCheckMode = msdfgen::ErrorCorrectionConfig::ALWAYS_CHECK_DISTANCE;
    } else {
        throw std::runtime_error("msdf-atlas-gen: unknown error correction mode: " + value);
    }
    explicit_mode = true;
}

msdf_atlas::ImageFormat image_format_from_path(const std::string& path)
{
    auto ends_with = [&path](const char* suffix) {
        size_t suffix_len = std::strlen(suffix);
        if (path.size() < suffix_len) {
            return false;
        }
        for (size_t i = 0; i < suffix_len; ++i) {
            char a = static_cast<char>(std::tolower(path[path.size() - suffix_len + i]));
            char b = static_cast<char>(std::tolower(suffix[i]));
            if (a != b) {
                return false;
            }
        }
        return true;
    };

    if (ends_with(".png")) {
        return msdf_atlas::ImageFormat::PNG;
    }
    if (ends_with(".bmp")) {
        return msdf_atlas::ImageFormat::BMP;
    }
    if (ends_with(".tiff") || ends_with(".tif")) {
        return msdf_atlas::ImageFormat::TIFF;
    }
    if (ends_with(".rgba")) {
        return msdf_atlas::ImageFormat::RGBA;
    }
    if (ends_with(".fl32")) {
        return msdf_atlas::ImageFormat::FL32;
    }
    if (ends_with(".txt")) {
        return msdf_atlas::ImageFormat::TEXT;
    }
    if (ends_with(".bin")) {
        return msdf_atlas::ImageFormat::BINARY;
    }
    return msdf_atlas::ImageFormat::UNSPECIFIED;
}

FontInputSpec parse_font_input(const sol::table& tbl)
{
    FontInputSpec input;
    sol::optional<std::string> font = tbl["font"];
    sol::optional<std::string> varfont = tbl["varfont"];
    if (font && varfont) {
        throw std::runtime_error("msdf-atlas-gen: font and varfont are mutually exclusive");
    }
    if (varfont) {
        input.font_filename = *varfont;
        input.variable_font = true;
    } else if (font) {
        input.font_filename = *font;
    }

    sol::optional<std::string> charset = tbl["charset"];
    sol::optional<std::string> glyphset = tbl["glyphset"];
    sol::optional<std::string> chars = tbl["chars"];
    sol::optional<std::string> glyphs = tbl["glyphs"];
    sol::optional<bool> allglyphs = tbl["allglyphs"];

    if (glyphset) {
        input.glyph_identifier_type = msdf_atlas::GlyphIdentifierType::GLYPH_INDEX;
        input.charset_filename = *glyphset;
    }
    if (glyphs) {
        input.glyph_identifier_type = msdf_atlas::GlyphIdentifierType::GLYPH_INDEX;
        input.charset_string = *glyphs;
    }
    if (charset) {
        input.glyph_identifier_type = msdf_atlas::GlyphIdentifierType::UNICODE_CODEPOINT;
        input.charset_filename = *charset;
    }
    if (chars) {
        input.glyph_identifier_type = msdf_atlas::GlyphIdentifierType::UNICODE_CODEPOINT;
        input.charset_string = *chars;
    }
    if (allglyphs) {
        input.all_glyphs = *allglyphs;
    }

    sol::optional<double> fontscale = tbl["fontscale"];
    if (fontscale) {
        input.font_scale = *fontscale;
    }
    sol::optional<std::string> fontname = tbl["fontname"];
    if (fontname) {
        input.font_name = *fontname;
    }

    return input;
}

MsdfAtlasRequest parse_request(const sol::table& options)
{
    MsdfAtlasRequest request;
    MsdfAtlasConfig& config = request.config;

    sol::optional<sol::table> fonts_table = options["fonts"];
    if (fonts_table) {
        for (auto& item : *fonts_table) {
            if (!item.second.is<sol::table>()) {
                throw std::runtime_error("msdf-atlas-gen: fonts entries must be tables");
            }
            request.fonts.push_back(parse_font_input(item.second.as<sol::table>()));
        }
    } else {
        request.fonts.push_back(parse_font_input(options));
    }

    for (auto& font : request.fonts) {
        if (font.font_filename.empty()) {
            throw std::runtime_error("msdf-atlas-gen: font path is required");
        }
    }

    sol::optional<std::string> type = options["type"];
    if (type) {
        config.image_type = parse_image_type(*type);
    }
    sol::optional<std::string> format = options["format"];
    if (format) {
        config.image_format = parse_image_format(*format);
    }
    sol::optional<std::string> yorigin = options["yorigin"];
    if (yorigin) {
        config.y_direction = parse_yorigin(*yorigin);
    }

    sol::optional<sol::table> dimensions = options["dimensions"];
    if (dimensions) {
        sol::optional<int> width = (*dimensions)["width"];
        sol::optional<int> height = (*dimensions)["height"];
        if (!width || !height || *width <= 0 || *height <= 0) {
            throw std::runtime_error("msdf-atlas-gen: dimensions must include positive width and height");
        }
        config.width = *width;
        config.height = *height;
    }

    sol::optional<std::string> atlas_constraint = options["constraint"];
    if (atlas_constraint) {
        request.atlas_constraint = parse_dimensions_constraint(*atlas_constraint);
    }

    sol::optional<bool> uniformgrid = options["uniformgrid"];
    if (uniformgrid && *uniformgrid) {
        request.packing_style = msdf_atlas::PackingStyle::GRID;
    }
    sol::optional<int> uniformcols = options["uniformcols"];
    if (uniformcols) {
        if (*uniformcols <= 0) {
            throw std::runtime_error("msdf-atlas-gen: uniformcols must be positive");
        }
        request.packing_style = msdf_atlas::PackingStyle::GRID;
        config.grid.cols = *uniformcols;
    }
    sol::optional<sol::table> uniformcell = options["uniformcell"];
    if (uniformcell) {
        sol::optional<int> width = (*uniformcell)["width"];
        sol::optional<int> height = (*uniformcell)["height"];
        if (!width || !height || *width <= 0 || *height <= 0) {
            throw std::runtime_error("msdf-atlas-gen: uniformcell must include positive width and height");
        }
        request.packing_style = msdf_atlas::PackingStyle::GRID;
        request.fixed_cell_width = *width;
        request.fixed_cell_height = *height;
    }
    sol::optional<std::string> uniformcellconstraint = options["uniformcellconstraint"];
    if (uniformcellconstraint) {
        request.packing_style = msdf_atlas::PackingStyle::GRID;
        request.cell_constraint = parse_dimensions_constraint(*uniformcellconstraint);
    }
    sol::optional<std::string> uniformorigin = options["uniformorigin"];
    if (uniformorigin) {
        request.packing_style = msdf_atlas::PackingStyle::GRID;
        parse_origin_flags(*uniformorigin, config.grid.fixed_origin_x, config.grid.fixed_origin_y, "uniformorigin");
    }

    sol::optional<std::string> imageout = options["imageout"];
    if (imageout) {
        config.image_filename = *imageout;
    }
    sol::optional<std::string> json = options["json"];
    if (json) {
        config.json_filename = *json;
    }
    sol::optional<std::string> csv = options["csv"];
    if (csv) {
        config.csv_filename = *csv;
    }
    sol::optional<std::string> arfont = options["arfont"];
    if (arfont) {
        config.artery_font_filename = *arfont;
    }
    sol::optional<sol::table> shadron = options["shadronpreview"];
    if (shadron) {
        sol::optional<std::string> path = (*shadron)["path"];
        sol::optional<std::string> text = (*shadron)["text"];
        if (!path || !text) {
            throw std::runtime_error("msdf-atlas-gen: shadronpreview requires path and text");
        }
        config.shadron_preview_filename = *path;
        config.shadron_preview_text = *text;
    }

    sol::optional<double> size = options["size"];
    if (size) {
        if (*size <= 0.0) {
            throw std::runtime_error("msdf-atlas-gen: size must be positive");
        }
        config.em_size = *size;
    }
    sol::optional<double> minsize = options["minsize"];
    if (minsize) {
        if (*minsize <= 0.0) {
            throw std::runtime_error("msdf-atlas-gen: minsize must be positive");
        }
        request.min_em_size = *minsize;
    }
    sol::optional<double> emrange = options["emrange"];
    if (emrange) {
        if (*emrange == 0.0) {
            throw std::runtime_error("msdf-atlas-gen: emrange must be non-zero");
        }
        request.range_units_em = true;
        request.range_value = msdfgen::Range(*emrange);
        request.range_value_set = true;
    }
    sol::optional<double> pxrange = options["pxrange"];
    if (pxrange) {
        if (*pxrange == 0.0) {
            throw std::runtime_error("msdf-atlas-gen: pxrange must be non-zero");
        }
        request.range_units_em = false;
        request.range_value = msdfgen::Range(*pxrange);
        request.range_value_set = true;
    }
    sol::optional<sol::table> aemrange = options["aemrange"];
    if (aemrange) {
        sol::optional<double> min = (*aemrange)[1];
        sol::optional<double> max = (*aemrange)[2];
        if (!min || !max || *min == *max) {
            throw std::runtime_error("msdf-atlas-gen: aemrange requires two distinct values");
        }
        request.range_units_em = true;
        request.range_value = msdfgen::Range(*min, *max);
        request.range_value_set = true;
    }
    sol::optional<sol::table> apxrange = options["apxrange"];
    if (apxrange) {
        sol::optional<double> min = (*apxrange)[1];
        sol::optional<double> max = (*apxrange)[2];
        if (!min || !max || *min == *max) {
            throw std::runtime_error("msdf-atlas-gen: apxrange requires two distinct values");
        }
        request.range_units_em = false;
        request.range_value = msdfgen::Range(*min, *max);
        request.range_value_set = true;
    }

    sol::optional<std::string> pxalign = options["pxalign"];
    if (pxalign) {
        parse_origin_flags(*pxalign, config.px_align_origin_x, config.px_align_origin_y, "pxalign");
    }

    sol::optional<bool> kerning = options["kerning"];
    if (kerning) {
        config.kerning = *kerning;
    }
    sol::optional<bool> nokerning = options["nokerning"];
    if (nokerning && *nokerning) {
        config.kerning = false;
    }

    sol::optional<sol::object> empadding = options["empadding"];
    if (empadding) {
        request.inner_padding = parse_padding(*empadding, "empadding");
        request.inner_padding_em = true;
    }
    sol::optional<sol::object> pxpadding = options["pxpadding"];
    if (pxpadding) {
        request.inner_padding = parse_padding(*pxpadding, "pxpadding");
        request.inner_padding_em = false;
    }
    sol::optional<sol::object> outerempadding = options["outerempadding"];
    if (outerempadding) {
        request.outer_padding = parse_padding(*outerempadding, "outerempadding");
        request.outer_padding_em = true;
    }
    sol::optional<sol::object> outerpxpadding = options["outerpxpadding"];
    if (outerpxpadding) {
        request.outer_padding = parse_padding(*outerpxpadding, "outerpxpadding");
        request.outer_padding_em = false;
    }

    sol::optional<double> angle = options["angle"];
    if (angle) {
        if (*angle <= 0.0) {
            throw std::runtime_error("msdf-atlas-gen: angle must be positive");
        }
        config.angle_threshold = *angle;
    }

    sol::optional<std::string> coloring = options["coloringstrategy"];
    if (coloring) {
        if (*coloring == "simple") {
            config.edge_coloring = &msdfgen::edgeColoringSimple;
            config.expensive_coloring = false;
        } else if (*coloring == "inktrap") {
            config.edge_coloring = &msdfgen::edgeColoringInkTrap;
            config.expensive_coloring = false;
        } else if (*coloring == "distance") {
            config.edge_coloring = &msdfgen::edgeColoringByDistance;
            config.expensive_coloring = true;
        } else {
            throw std::runtime_error("msdf-atlas-gen: unknown coloring strategy: " + *coloring);
        }
    }

    sol::optional<std::string> errorcorrection = options["errorcorrection"];
    if (errorcorrection) {
        apply_error_correction(*errorcorrection, config.generator_attributes, request.explicit_error_correction);
    }
    sol::optional<double> errordeviationratio = options["errordeviationratio"];
    if (errordeviationratio) {
        if (*errordeviationratio <= 0.0) {
            throw std::runtime_error("msdf-atlas-gen: errordeviationratio must be positive");
        }
        config.generator_attributes.config.errorCorrection.minDeviationRatio = *errordeviationratio;
    }
    sol::optional<double> errorimproveratio = options["errorimproveratio"];
    if (errorimproveratio) {
        if (*errorimproveratio <= 0.0) {
            throw std::runtime_error("msdf-atlas-gen: errorimproveratio must be positive");
        }
        config.generator_attributes.config.errorCorrection.minImproveRatio = *errorimproveratio;
    }

    sol::optional<double> miterlimit = options["miterlimit"];
    if (miterlimit) {
        if (*miterlimit < 0.0) {
            throw std::runtime_error("msdf-atlas-gen: miterlimit must be non-negative");
        }
        config.miter_limit = *miterlimit;
    }

    sol::optional<bool> preprocess = options["preprocess"];
    if (preprocess) {
        config.preprocess_geometry = *preprocess;
    }
    sol::optional<bool> nopreprocess = options["nopreprocess"];
    if (nopreprocess && *nopreprocess) {
        config.preprocess_geometry = false;
    }

    sol::optional<bool> overlap = options["overlap"];
    if (overlap) {
        config.generator_attributes.config.overlapSupport = *overlap;
        request.explicit_overlap = true;
    }
    sol::optional<bool> nooverlap = options["nooverlap"];
    if (nooverlap && *nooverlap) {
        config.generator_attributes.config.overlapSupport = false;
        request.explicit_overlap = true;
    }

    sol::optional<bool> scanline = options["scanline"];
    if (scanline) {
        config.generator_attributes.scanlinePass = *scanline;
        request.explicit_scanline = true;
    }
    sol::optional<bool> noscanline = options["noscanline"];
    if (noscanline && *noscanline) {
        config.generator_attributes.scanlinePass = false;
        request.explicit_scanline = true;
    }

    sol::optional<unsigned long long> seed = options["seed"];
    if (seed) {
        config.coloring_seed = *seed;
    }

    sol::optional<int> threads = options["threads"];
    if (threads) {
        if (*threads < 0) {
            throw std::runtime_error("msdf-atlas-gen: threads must be non-negative");
        }
        config.thread_count = *threads;
    }

    return request;
}

struct MsdfAtlasResult {
    int width = 0;
    int height = 0;
    double em_size = 0.0;
    double px_range = 0.0;
    int glyph_count = 0;
};

MsdfAtlasResult generate_msdf_atlas(const MsdfAtlasRequest& request)
{
    MsdfAtlasConfig config = request.config;
    const bool fixed_dimensions = config.width > 0 && config.height > 0;
    const bool fixed_cell_dimensions = request.fixed_cell_width > 0 && request.fixed_cell_height > 0;
    msdf_atlas::PackingStyle packing_style = request.packing_style;
    msdf_atlas::DimensionsConstraint atlas_constraint = request.atlas_constraint;

    if (!request.explicit_overlap) {
        config.generator_attributes.config.overlapSupport = !config.preprocess_geometry;
    }
    if (!request.explicit_scanline) {
        config.generator_attributes.scanlinePass = !config.preprocess_geometry;
    }

    std::vector<msdf_atlas::GlyphGeometry> glyphs;
    std::vector<msdf_atlas::FontGeometry> fonts;
    bool any_codepoints = false;

    FontContext font_context;

    for (const FontInputSpec& font_input : request.fonts) {
        if (font_context.font) {
            msdfgen::destroyFont(font_context.font);
            font_context.font = nullptr;
        }
        if (font_input.variable_font) {
#ifndef MSDFGEN_DISABLE_VARIABLE_FONTS
            if (!std::filesystem::exists(font_input.font_filename)) {
                throw std::runtime_error("msdf-atlas-gen: font file not found: " + font_input.font_filename);
            }
            if (!std::filesystem::is_regular_file(font_input.font_filename)) {
                throw std::runtime_error("msdf-atlas-gen: font path is not a file: " + font_input.font_filename);
            }
            font_context.font = load_var_font(font_context.freetype, font_input.font_filename);
#else
            throw std::runtime_error("msdf-atlas-gen: variable fonts are disabled in msdfgen");
#endif
            if (!font_context.font) {
                throw std::runtime_error("msdf-atlas-gen: failed to load variable font: " + font_input.font_filename);
            }
        } else {
            font_context.load_font(font_input.font_filename);
        }

        double scale = font_input.font_scale > 0 ? font_input.font_scale : 1.0;
        msdf_atlas::FontGeometry font_geometry(&glyphs);

        int glyphs_loaded = -1;
        if (font_input.all_glyphs || font_input.glyph_identifier_type == msdf_atlas::GlyphIdentifierType::GLYPH_INDEX) {
            unsigned glyph_count = 0;
            msdfgen::getGlyphCount(glyph_count, font_context.font);
            if (font_input.all_glyphs && glyph_count > 0) {
                glyphs_loaded = font_geometry.loadGlyphRange(font_context.font, scale, 0, glyph_count, config.preprocess_geometry, config.kerning);
            } else {
                msdf_atlas::Charset glyphset;
                if (!font_input.charset_filename.empty()) {
                    if (!glyphset.load(font_input.charset_filename.c_str(), true)) {
                        throw std::runtime_error("msdf-atlas-gen: failed to load glyph set file");
                    }
                } else if (!font_input.charset_string.empty()) {
                    if (!glyphset.parse(font_input.charset_string.c_str(), font_input.charset_string.size(), true)) {
                        throw std::runtime_error("msdf-atlas-gen: failed to parse glyph set string");
                    }
                } else {
                    glyphs_loaded = font_geometry.loadGlyphRange(font_context.font, scale, 0, glyph_count, config.preprocess_geometry, config.kerning);
                }
                if (glyphs_loaded < 0 && !glyphset.empty()) {
                    glyphs_loaded = font_geometry.loadGlyphset(font_context.font, scale, glyphset, config.preprocess_geometry, config.kerning);
                }
            }
        } else {
            msdf_atlas::Charset charset;
            if (!font_input.charset_filename.empty()) {
                if (!charset.load(font_input.charset_filename.c_str(), false)) {
                    throw std::runtime_error("msdf-atlas-gen: failed to load charset file");
                }
            } else if (!font_input.charset_string.empty()) {
                if (!charset.parse(font_input.charset_string.c_str(), font_input.charset_string.size(), false)) {
                    throw std::runtime_error("msdf-atlas-gen: failed to parse charset string");
                }
            } else {
                charset = msdf_atlas::Charset::ASCII;
            }
            glyphs_loaded = font_geometry.loadCharset(font_context.font, scale, charset, config.preprocess_geometry, config.kerning);
            any_codepoints |= glyphs_loaded > 0;
        }

        if (glyphs_loaded < 0) {
            throw std::runtime_error("msdf-atlas-gen: failed to load glyphs");
        }

        if (!font_input.font_name.empty()) {
            font_geometry.setName(font_input.font_name.c_str());
        }

        fonts.push_back(std::move(font_geometry));
    }

    if (packing_style == msdf_atlas::PackingStyle::TIGHT && atlas_constraint == msdf_atlas::DimensionsConstraint::NONE) {
        atlas_constraint = msdf_atlas::DimensionsConstraint::MULTIPLE_OF_FOUR_SQUARE;
    }

    if (!(config.image_type == msdf_atlas::ImageType::PSDF || config.image_type == msdf_atlas::ImageType::MSDF || config.image_type == msdf_atlas::ImageType::MTSDF)) {
        config.miter_limit = 0.0;
    }

    double min_em_size = request.min_em_size;
    if (config.em_size > min_em_size) {
        min_em_size = config.em_size;
    }
    if (!fixed_dimensions && !fixed_cell_dimensions && min_em_size <= 0.0) {
        min_em_size = kDefaultEmSize;
    }

    msdfgen::Range range_value = request.range_value_set ? request.range_value : msdfgen::Range(0.0);
    bool range_units_em = request.range_units_em;
    if (config.image_type == msdf_atlas::ImageType::HARD_MASK || config.image_type == msdf_atlas::ImageType::SOFT_MASK) {
        range_units_em = false;
        range_value = msdfgen::Range(1.0);
    } else if (range_value.lower == range_value.upper) {
        range_units_em = false;
        range_value = msdfgen::Range(kDefaultPxRange);
    }

    if (config.kerning && config.artery_font_filename.empty() && config.json_filename.empty() && config.shadron_preview_filename.empty()) {
        config.kerning = false;
    }

    if (config.thread_count <= 0) {
        config.thread_count = static_cast<int>(std::max(1u, std::thread::hardware_concurrency()));
    }

    if (config.generator_attributes.scanlinePass) {
        if (request.explicit_error_correction &&
            config.generator_attributes.config.errorCorrection.distanceCheckMode != msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE) {
            config.generator_attributes.config.errorCorrection.distanceCheckMode = msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE;
        }
        config.generator_attributes.config.errorCorrection.distanceCheckMode = msdfgen::ErrorCorrectionConfig::DO_NOT_CHECK_DISTANCE;
    }

    msdf_atlas::Padding inner_em_padding;
    msdf_atlas::Padding outer_em_padding;
    msdf_atlas::Padding inner_px_padding;
    msdf_atlas::Padding outer_px_padding;

    if (request.inner_padding_em) {
        inner_em_padding = request.inner_padding;
    } else {
        inner_px_padding = request.inner_padding;
    }
    if (request.outer_padding_em) {
        outer_em_padding = request.outer_padding;
    } else {
        outer_px_padding = request.outer_padding;
    }

    const bool layout_only = config.artery_font_filename.empty() && config.image_filename.empty();

    int spacing = (config.image_type == msdf_atlas::ImageType::MSDF || config.image_type == msdf_atlas::ImageType::MTSDF) ? 0 : -1;
    double uniform_origin_x = 0.0;
    double uniform_origin_y = 0.0;

    if (packing_style == msdf_atlas::PackingStyle::TIGHT) {
        msdf_atlas::TightAtlasPacker atlas_packer;
        if (fixed_dimensions) {
            atlas_packer.setDimensions(config.width, config.height);
        } else {
            atlas_packer.setDimensionsConstraint(atlas_constraint);
        }
        atlas_packer.setSpacing(spacing);
        if (config.em_size > 0.0) {
            atlas_packer.setScale(config.em_size);
        } else {
            atlas_packer.setMinimumScale(min_em_size);
        }
        if (range_units_em) {
            atlas_packer.setUnitRange(range_value);
        } else {
            atlas_packer.setPixelRange(range_value);
        }
        atlas_packer.setMiterLimit(config.miter_limit);
        atlas_packer.setOriginPixelAlignment(config.px_align_origin_x, config.px_align_origin_y);
        atlas_packer.setInnerUnitPadding(inner_em_padding);
        atlas_packer.setOuterUnitPadding(outer_em_padding);
        atlas_packer.setInnerPixelPadding(inner_px_padding);
        atlas_packer.setOuterPixelPadding(outer_px_padding);
        int remaining = atlas_packer.pack(glyphs.data(), static_cast<int>(glyphs.size()));
        if (remaining != 0) {
            throw std::runtime_error("msdf-atlas-gen: failed to pack glyphs into atlas");
        }
        atlas_packer.getDimensions(config.width, config.height);
        if (!(config.width > 0 && config.height > 0)) {
            throw std::runtime_error("msdf-atlas-gen: unable to determine atlas size");
        }
        config.em_size = atlas_packer.getScale();
        config.px_range = atlas_packer.getPixelRange();
    } else {
        msdf_atlas::GridAtlasPacker atlas_packer;
        atlas_packer.setFixedOrigin(config.grid.fixed_origin_x, config.grid.fixed_origin_y);
        if (fixed_cell_dimensions) {
            atlas_packer.setCellDimensions(request.fixed_cell_width, request.fixed_cell_height);
        } else {
            atlas_packer.setCellDimensionsConstraint(request.cell_constraint);
        }
        if (config.grid.cols > 0) {
            atlas_packer.setColumns(config.grid.cols);
        }
        if (fixed_dimensions) {
            atlas_packer.setDimensions(config.width, config.height);
        } else {
            atlas_packer.setDimensionsConstraint(atlas_constraint);
        }
        atlas_packer.setSpacing(spacing);
        if (config.em_size > 0.0) {
            atlas_packer.setScale(config.em_size);
        } else {
            atlas_packer.setMinimumScale(min_em_size);
        }
        if (range_units_em) {
            atlas_packer.setUnitRange(range_value);
        } else {
            atlas_packer.setPixelRange(range_value);
        }
        atlas_packer.setMiterLimit(config.miter_limit);
        atlas_packer.setOriginPixelAlignment(config.px_align_origin_x, config.px_align_origin_y);
        atlas_packer.setInnerUnitPadding(inner_em_padding);
        atlas_packer.setOuterUnitPadding(outer_em_padding);
        atlas_packer.setInnerPixelPadding(inner_px_padding);
        atlas_packer.setOuterPixelPadding(outer_px_padding);
        int remaining = atlas_packer.pack(glyphs.data(), static_cast<int>(glyphs.size()));
        if (remaining != 0) {
            throw std::runtime_error("msdf-atlas-gen: failed to pack glyphs into atlas");
        }
        if (atlas_packer.hasCutoff()) {
            throw std::runtime_error("msdf-atlas-gen: grid cell constraints cut off glyphs");
        }
        atlas_packer.getDimensions(config.width, config.height);
        if (!(config.width > 0 && config.height > 0)) {
            throw std::runtime_error("msdf-atlas-gen: unable to determine atlas size");
        }
        config.em_size = atlas_packer.getScale();
        config.px_range = atlas_packer.getPixelRange();
        atlas_packer.getCellDimensions(config.grid.cell_width, config.grid.cell_height);
        config.grid.cols = atlas_packer.getColumns();
        config.grid.rows = atlas_packer.getRows();
        if (config.grid.fixed_origin_x || config.grid.fixed_origin_y) {
            atlas_packer.getFixedOrigin(uniform_origin_x, uniform_origin_y);
        }
    }

    if (config.image_filename.empty() && config.json_filename.empty() && config.csv_filename.empty() && config.shadron_preview_filename.empty() && config.artery_font_filename.empty()) {
        throw std::runtime_error("msdf-atlas-gen: no output specified");
    }

    if (!config.shadron_preview_filename.empty() && config.image_filename.empty()) {
        throw std::runtime_error("msdf-atlas-gen: shadron preview requires imageout");
    }

    msdf_atlas::ImageFormat image_extension = msdf_atlas::ImageFormat::UNSPECIFIED;
    if (!config.image_filename.empty()) {
        image_extension = image_format_from_path(config.image_filename);
    }
    if (config.image_format == msdf_atlas::ImageFormat::UNSPECIFIED) {
        config.image_format = image_extension != msdf_atlas::ImageFormat::UNSPECIFIED ? image_extension : msdf_atlas::ImageFormat::PNG;
    }

#ifndef MSDF_ATLAS_NO_ARTERY_FONT
    if (!config.artery_font_filename.empty()) {
        if (!(config.image_format == msdf_atlas::ImageFormat::PNG || config.image_format == msdf_atlas::ImageFormat::BINARY || config.image_format == msdf_atlas::ImageFormat::BINARY_FLOAT)) {
            throw std::runtime_error("msdf-atlas-gen: artery font output requires png/bin/binfloat image format");
        }
    }
#endif

    if (!layout_only) {
        if (config.image_type == msdf_atlas::ImageType::MSDF || config.image_type == msdf_atlas::ImageType::MTSDF) {
            if (config.expensive_coloring) {
                msdf_atlas::Workload([&glyphs, &config](int i, int) -> bool {
                    unsigned long long glyph_seed = (6364136223846793005ull * (config.coloring_seed ^ i) + 1442695040888963407ull) * !!config.coloring_seed;
                    glyphs[i].edgeColoring(config.edge_coloring, config.angle_threshold, glyph_seed);
                    return true;
                }, glyphs.size()).finish(config.thread_count);
            } else {
                unsigned long long glyph_seed = config.coloring_seed;
                for (msdf_atlas::GlyphGeometry& glyph : glyphs) {
                    glyph_seed *= 6364136223846793005ull;
                    glyph.edgeColoring(config.edge_coloring, config.angle_threshold, glyph_seed);
                }
            }
        }

        const bool floating_point_format = (config.image_format == msdf_atlas::ImageFormat::TIFF || config.image_format == msdf_atlas::ImageFormat::FL32 ||
                                            config.image_format == msdf_atlas::ImageFormat::TEXT_FLOAT ||
                                            config.image_format == msdf_atlas::ImageFormat::BINARY_FLOAT ||
                                            config.image_format == msdf_atlas::ImageFormat::BINARY_FLOAT_BE);

        auto save_outputs = [&](auto& bitmap) {
            bitmap.reorient(config.y_direction);
            if (!config.image_filename.empty()) {
                if (!msdf_atlas::saveImage(bitmap, config.image_format, config.image_filename.c_str())) {
                    throw std::runtime_error("msdf-atlas-gen: failed to write image output");
                }
            }
#ifndef MSDF_ATLAS_NO_ARTERY_FONT
            if (!config.artery_font_filename.empty()) {
                msdf_atlas::ArteryFontExportProperties props;
                props.fontSize = config.em_size;
                props.pxRange = config.px_range;
                props.imageType = config.image_type;
                props.imageFormat = config.image_format;
                if (!msdf_atlas::exportArteryFont<float>(fonts.data(), static_cast<int>(fonts.size()), bitmap, config.artery_font_filename.c_str(), props)) {
                    throw std::runtime_error("msdf-atlas-gen: failed to write artery font output");
                }
            }
#endif
        };

        switch (config.image_type) {
            case msdf_atlas::ImageType::HARD_MASK: {
                if (floating_point_format) {
                    msdf_atlas::ImmediateAtlasGenerator<float, 1, msdf_atlas::scanlineGenerator, msdf_atlas::BitmapAtlasStorage<float, 1>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<float, 1> bitmap = (msdfgen::BitmapConstSection<float, 1>) generator.atlasStorage();
                    save_outputs(bitmap);
                } else {
                    msdf_atlas::ImmediateAtlasGenerator<float, 1, msdf_atlas::scanlineGenerator, msdf_atlas::BitmapAtlasStorage<msdf_atlas::byte, 1>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<msdf_atlas::byte, 1> bitmap = (msdfgen::BitmapConstSection<msdf_atlas::byte, 1>) generator.atlasStorage();
                    save_outputs(bitmap);
                }
                break;
            }
            case msdf_atlas::ImageType::SOFT_MASK:
            case msdf_atlas::ImageType::SDF: {
                if (floating_point_format) {
                    msdf_atlas::ImmediateAtlasGenerator<float, 1, msdf_atlas::sdfGenerator, msdf_atlas::BitmapAtlasStorage<float, 1>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<float, 1> bitmap = (msdfgen::BitmapConstSection<float, 1>) generator.atlasStorage();
                    save_outputs(bitmap);
                } else {
                    msdf_atlas::ImmediateAtlasGenerator<float, 1, msdf_atlas::sdfGenerator, msdf_atlas::BitmapAtlasStorage<msdf_atlas::byte, 1>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<msdf_atlas::byte, 1> bitmap = (msdfgen::BitmapConstSection<msdf_atlas::byte, 1>) generator.atlasStorage();
                    save_outputs(bitmap);
                }
                break;
            }
            case msdf_atlas::ImageType::PSDF: {
                if (floating_point_format) {
                    msdf_atlas::ImmediateAtlasGenerator<float, 1, msdf_atlas::psdfGenerator, msdf_atlas::BitmapAtlasStorage<float, 1>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<float, 1> bitmap = (msdfgen::BitmapConstSection<float, 1>) generator.atlasStorage();
                    save_outputs(bitmap);
                } else {
                    msdf_atlas::ImmediateAtlasGenerator<float, 1, msdf_atlas::psdfGenerator, msdf_atlas::BitmapAtlasStorage<msdf_atlas::byte, 1>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<msdf_atlas::byte, 1> bitmap = (msdfgen::BitmapConstSection<msdf_atlas::byte, 1>) generator.atlasStorage();
                    save_outputs(bitmap);
                }
                break;
            }
            case msdf_atlas::ImageType::MSDF: {
                if (floating_point_format) {
                    msdf_atlas::ImmediateAtlasGenerator<float, 3, msdf_atlas::msdfGenerator, msdf_atlas::BitmapAtlasStorage<float, 3>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<float, 3> bitmap = (msdfgen::BitmapConstSection<float, 3>) generator.atlasStorage();
                    save_outputs(bitmap);
                } else {
                    msdf_atlas::ImmediateAtlasGenerator<float, 3, msdf_atlas::msdfGenerator, msdf_atlas::BitmapAtlasStorage<msdf_atlas::byte, 3>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<msdf_atlas::byte, 3> bitmap = (msdfgen::BitmapConstSection<msdf_atlas::byte, 3>) generator.atlasStorage();
                    save_outputs(bitmap);
                }
                break;
            }
            case msdf_atlas::ImageType::MTSDF: {
                if (floating_point_format) {
                    msdf_atlas::ImmediateAtlasGenerator<float, 4, msdf_atlas::mtsdfGenerator, msdf_atlas::BitmapAtlasStorage<float, 4>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<float, 4> bitmap = (msdfgen::BitmapConstSection<float, 4>) generator.atlasStorage();
                    save_outputs(bitmap);
                } else {
                    msdf_atlas::ImmediateAtlasGenerator<float, 4, msdf_atlas::mtsdfGenerator, msdf_atlas::BitmapAtlasStorage<msdf_atlas::byte, 4>> generator(config.width, config.height);
                    generator.setAttributes(config.generator_attributes);
                    generator.setThreadCount(config.thread_count);
                    generator.generate(glyphs.data(), static_cast<int>(glyphs.size()));
                    msdfgen::BitmapConstSection<msdf_atlas::byte, 4> bitmap = (msdfgen::BitmapConstSection<msdf_atlas::byte, 4>) generator.atlasStorage();
                    save_outputs(bitmap);
                }
                break;
            }
        }
    }

    if (!config.csv_filename.empty()) {
        if (!msdf_atlas::exportCSV(fonts.data(), static_cast<int>(fonts.size()), config.width, config.height, config.y_direction, config.csv_filename.c_str())) {
            throw std::runtime_error("msdf-atlas-gen: failed to write csv output");
        }
    }

    if (!config.json_filename.empty()) {
        msdf_atlas::JsonAtlasMetrics json_metrics = {};
        msdf_atlas::JsonAtlasMetrics::GridMetrics grid_metrics = {};
        json_metrics.distanceRange = config.px_range;
        json_metrics.size = config.em_size;
        json_metrics.width = config.width;
        json_metrics.height = config.height;
        json_metrics.yDirection = config.y_direction;
        if (packing_style == msdf_atlas::PackingStyle::GRID) {
            grid_metrics.cellWidth = config.grid.cell_width;
            grid_metrics.cellHeight = config.grid.cell_height;
            grid_metrics.columns = config.grid.cols;
            grid_metrics.rows = config.grid.rows;
            if (config.grid.fixed_origin_x) {
                grid_metrics.originX = &uniform_origin_x;
            }
            if (config.grid.fixed_origin_y) {
                grid_metrics.originY = &uniform_origin_y;
            }
            grid_metrics.spacing = spacing;
            json_metrics.grid = &grid_metrics;
        }
        if (!msdf_atlas::exportJSON(fonts.data(), static_cast<int>(fonts.size()), config.image_type, json_metrics, config.json_filename.c_str(), config.kerning)) {
            throw std::runtime_error("msdf-atlas-gen: failed to write json output");
        }
    }

    if (!config.shadron_preview_filename.empty() && !config.shadron_preview_text.empty()) {
        if (!any_codepoints) {
            throw std::runtime_error("msdf-atlas-gen: shadron preview requires Unicode codepoints");
        }
        std::vector<msdf_atlas::unicode_t> preview_text;
        msdf_atlas::utf8Decode(preview_text, config.shadron_preview_text.c_str());
        preview_text.push_back(0);
        const bool floating_point_format = (config.image_format == msdf_atlas::ImageFormat::TIFF || config.image_format == msdf_atlas::ImageFormat::FL32 ||
                                            config.image_format == msdf_atlas::ImageFormat::TEXT_FLOAT ||
                                            config.image_format == msdf_atlas::ImageFormat::BINARY_FLOAT ||
                                            config.image_format == msdf_atlas::ImageFormat::BINARY_FLOAT_BE);
        if (!msdf_atlas::generateShadronPreview(fonts.data(), static_cast<int>(fonts.size()), config.image_type, config.width, config.height, config.px_range,
                                                preview_text.data(), config.image_filename.c_str(), floating_point_format, config.shadron_preview_filename.c_str())) {
            throw std::runtime_error("msdf-atlas-gen: failed to write shadron preview");
        }
    }

    MsdfAtlasResult result;
    result.width = config.width;
    result.height = config.height;
    result.em_size = config.em_size;
    result.px_range = config.px_range.upper - config.px_range.lower;
    result.glyph_count = static_cast<int>(glyphs.size());
    return result;
}

sol::object msdf_atlas_generate(sol::this_state ts, const sol::table& options)
{
    sol::state_view lua(ts);
    MsdfAtlasRequest request = parse_request(options);
    MsdfAtlasResult result = generate_msdf_atlas(request);

    sol::table out = lua.create_table();
    out["width"] = result.width;
    out["height"] = result.height;
    out["em-size"] = result.em_size;
    out["px-range"] = result.px_range;
    out["glyph-count"] = result.glyph_count;
    return sol::make_object(lua, out);
}

sol::table create_msdf_atlas_table(sol::state_view lua)
{
    sol::table msdf_table = lua.create_table();
    msdf_table.set_function("generate", &msdf_atlas_generate);
    return msdf_table;
}

} // namespace

void lua_bind_msdf_atlas_gen(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("msdf-atlas-gen", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_msdf_atlas_table(lua);
    });
}
