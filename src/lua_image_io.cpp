#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#include <sol/sol.hpp>

#include <png.h>

#include "image_loader.h"

namespace {

std::size_t expected_size(int width, int height, int channels)
{
    if (width <= 0 || height <= 0 || channels <= 0) {
        throw std::runtime_error("image dimensions must be positive");
    }
    return static_cast<std::size_t>(width) *
           static_cast<std::size_t>(height) *
           static_cast<std::size_t>(channels);
}

std::string flip_vertical_bytes(int width, int height, int channels, const std::string& bytes)
{
    std::size_t expected = expected_size(width, height, channels);
    if (bytes.size() < expected) {
        throw std::runtime_error("pixel buffer is smaller than expected size");
    }
    std::string out;
    out.resize(expected);
    std::size_t row_bytes = static_cast<std::size_t>(width) * static_cast<std::size_t>(channels);
    const char* src = bytes.data();
    char* dst = out.data();
    for (int y = 0; y < height; y++) {
        const char* src_row = src + static_cast<std::size_t>(height - 1 - y) * row_bytes;
        char* dst_row = dst + static_cast<std::size_t>(y) * row_bytes;
        std::memcpy(dst_row, src_row, row_bytes);
    }
    return out;
}

sol::table read_png(sol::this_state ts, const std::string& path)
{
    ImageBuffer image;
    std::string error;
    if (!load_png_file(path, image, error)) {
        throw std::runtime_error("Failed to load image: " + path);
    }
    int width = image.width;
    int height = image.height;
    int channels = image.channels;
    std::size_t size = expected_size(width, height, channels);
    std::string bytes(reinterpret_cast<const char*>(image.pixels.get()), size);

    sol::state_view lua(ts);
    sol::table out = lua.create_table();
    out["width"] = width;
    out["height"] = height;
    out["channels"] = channels;
    out["bytes"] = bytes;
    return out;
}

void write_png(const std::string& path,
               int width,
               int height,
               int channels,
               const std::string& bytes,
               sol::optional<bool> flip_y)
{
    std::size_t expected = expected_size(width, height, channels);
    if (bytes.size() < expected) {
        throw std::runtime_error("pixel buffer is smaller than expected size");
    }
    int color_type = 0;
    if (channels == 4) {
        color_type = PNG_COLOR_TYPE_RGBA;
    } else if (channels == 3) {
        color_type = PNG_COLOR_TYPE_RGB;
    } else if (channels == 1) {
        color_type = PNG_COLOR_TYPE_GRAY;
    } else if (channels == 2) {
        color_type = PNG_COLOR_TYPE_GRAY_ALPHA;
    } else {
        throw std::runtime_error("unsupported PNG channel count");
    }

    FILE* fp = fopen(path.c_str(), "wb");
    if (!fp) {
        throw std::runtime_error("Failed to open PNG output file: " + path);
    }

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    if (!png) {
        fclose(fp);
        throw std::runtime_error("Failed to create PNG write struct");
    }
    png_infop info = png_create_info_struct(png);
    if (!info) {
        png_destroy_write_struct(&png, nullptr);
        fclose(fp);
        throw std::runtime_error("Failed to create PNG info struct");
    }
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_write_struct(&png, &info);
        fclose(fp);
        throw std::runtime_error("PNG write failed");
    }

    png_init_io(png, fp);
    png_set_IHDR(png, info, width, height, 8, color_type,
                 PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);

    std::size_t row_bytes = static_cast<std::size_t>(width) * static_cast<std::size_t>(channels);
    const unsigned char* data = reinterpret_cast<const unsigned char*>(bytes.data());
    std::vector<png_bytep> rows(static_cast<std::size_t>(height));
    bool flip = flip_y && *flip_y;
    for (int y = 0; y < height; y++) {
        int src = flip ? (height - 1 - y) : y;
        rows[static_cast<std::size_t>(y)] = const_cast<png_bytep>(data + static_cast<std::size_t>(src) * row_bytes);
    }

    png_write_image(png, rows.data());
    png_write_end(png, nullptr);
    png_destroy_write_struct(&png, &info);
    fclose(fp);
}

} // namespace

void lua_bind_image_io(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("image-io", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table image_io = lua_view.create_table();
        image_io.set_function("read-png", &read_png);
        image_io.set_function("write-png", &write_png);
        image_io.set_function("flip-vertical", &flip_vertical_bytes);
        return image_io;
    });
}
