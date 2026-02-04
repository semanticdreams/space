#include "image_loader.h"

#include <algorithm>
#include <cctype>
#include <csetjmp>
#include <cstdio>
#include <cstring>
#include <vector>

#include <jpeglib.h>
#include <png.h>

namespace {

struct PngErrorContext {
    std::string* error { nullptr };
};

void png_error_handler(png_structp png_ptr, png_const_charp message) {
    auto* ctx = static_cast<PngErrorContext*>(png_get_error_ptr(png_ptr));
    if (ctx && ctx->error) {
        *ctx->error = message ? message : "PNG decode failed";
    }
    longjmp(png_jmpbuf(png_ptr), 1);
}

void png_warning_handler(png_structp, png_const_charp) {
}

struct PngMemoryReader {
    const std::uint8_t* data { nullptr };
    std::size_t size { 0 };
    std::size_t offset { 0 };
};

void png_read_memory(png_structp png_ptr, png_bytep out_bytes, png_size_t byte_count_to_read) {
    auto* reader = static_cast<PngMemoryReader*>(png_get_io_ptr(png_ptr));
    if (!reader || !reader->data) {
        png_error(png_ptr, "PNG memory reader missing data");
    }
    if (reader->offset + byte_count_to_read > reader->size) {
        png_error(png_ptr, "PNG read beyond buffer");
    }
    std::memcpy(out_bytes, reader->data + reader->offset, byte_count_to_read);
    reader->offset += byte_count_to_read;
}

bool decode_png(png_structp png_ptr, png_infop info_ptr, ImageBuffer& out, std::string& error) {
    if (setjmp(png_jmpbuf(png_ptr))) {
        if (error.empty()) {
            error = "PNG decode failed";
        }
        return false;
    }

    png_read_info(png_ptr, info_ptr);

    png_uint_32 width = png_get_image_width(png_ptr, info_ptr);
    png_uint_32 height = png_get_image_height(png_ptr, info_ptr);
    int color_type = png_get_color_type(png_ptr, info_ptr);
    int bit_depth = png_get_bit_depth(png_ptr, info_ptr);

    if (bit_depth == 16) {
        png_set_strip_16(png_ptr);
    }
    if (color_type == PNG_COLOR_TYPE_PALETTE) {
        png_set_palette_to_rgb(png_ptr);
    }
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8) {
        png_set_expand_gray_1_2_4_to_8(png_ptr);
    }
    if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
        png_set_tRNS_to_alpha(png_ptr);
    }
    if (color_type == PNG_COLOR_TYPE_GRAY || color_type == PNG_COLOR_TYPE_GRAY_ALPHA) {
        png_set_gray_to_rgb(png_ptr);
    }
    if (color_type == PNG_COLOR_TYPE_RGB ||
        color_type == PNG_COLOR_TYPE_GRAY ||
        color_type == PNG_COLOR_TYPE_PALETTE) {
        png_set_filler(png_ptr, 0xFF, PNG_FILLER_AFTER);
    }

    png_read_update_info(png_ptr, info_ptr);

    png_size_t row_bytes = png_get_rowbytes(png_ptr, info_ptr);
    if (row_bytes == 0 || height == 0) {
        error = "PNG decode produced empty image";
        return false;
    }

    auto pixels = std::make_unique<std::uint8_t[]>(row_bytes * height);
    std::vector<png_bytep> rows(height);
    for (png_uint_32 y = 0; y < height; ++y) {
        rows[y] = pixels.get() + (y * row_bytes);
    }

    png_read_image(png_ptr, rows.data());
    png_read_end(png_ptr, nullptr);

    out.pixels = std::move(pixels);
    out.width = static_cast<int>(width);
    out.height = static_cast<int>(height);
    out.channels = 4;
    return true;
}

struct JpegErrorContext {
    jpeg_error_mgr base {};
    std::string* error { nullptr };
    jmp_buf jump;
};

void jpeg_error_handler(j_common_ptr cinfo) {
    auto* ctx = reinterpret_cast<JpegErrorContext*>(cinfo->err);
    if (ctx && ctx->error) {
        char buffer[JMSG_LENGTH_MAX] = {};
        (*cinfo->err->format_message)(cinfo, buffer);
        *ctx->error = buffer[0] != '\0' ? buffer : "JPEG decode failed";
    }
    longjmp(ctx->jump, 1);
}

bool decode_jpeg(jpeg_decompress_struct& cinfo, ImageBuffer& out, std::string& error) {
    if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK) {
        error = "JPEG header parse failed";
        return false;
    }

#if defined(JCS_EXT_RGBA)
    cinfo.out_color_space = JCS_EXT_RGBA;
    const int out_channels = 4;
#else
    cinfo.out_color_space = JCS_RGB;
    const int out_channels = 3;
#endif

    jpeg_start_decompress(&cinfo);

    const int width = static_cast<int>(cinfo.output_width);
    const int height = static_cast<int>(cinfo.output_height);
    if (width <= 0 || height <= 0) {
        error = "JPEG decode produced empty image";
        jpeg_finish_decompress(&cinfo);
        return false;
    }

    const std::size_t row_bytes = static_cast<std::size_t>(width) *
                                  static_cast<std::size_t>(out_channels);
    auto pixels = std::make_unique<std::uint8_t[]>(row_bytes * static_cast<std::size_t>(height));
    while (cinfo.output_scanline < cinfo.output_height) {
        auto* row = pixels.get() + (static_cast<std::size_t>(cinfo.output_scanline) * row_bytes);
        jpeg_read_scanlines(&cinfo, &row, 1);
    }

    jpeg_finish_decompress(&cinfo);

    out.pixels = std::move(pixels);
    out.width = width;
    out.height = height;
    out.channels = out_channels;
    return true;
}

std::string to_lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

bool has_png_header(const std::uint8_t* data, std::size_t size) {
    return data && size >= 8 && png_sig_cmp(const_cast<png_bytep>(data), 0, 8) == 0;
}

bool has_jpeg_header(const std::uint8_t* data, std::size_t size) {
    return data && size >= 2 && data[0] == 0xFF && data[1] == 0xD8;
}

} // namespace

bool load_png_file(const std::string& path, ImageBuffer& out, std::string& error) {
    out = {};
    error.clear();

    FILE* fp = std::fopen(path.c_str(), "rb");
    if (!fp) {
        error = "Unable to open PNG file: " + path;
        return false;
    }

    std::uint8_t header[8] = {};
    if (std::fread(header, 1, sizeof(header), fp) != sizeof(header)) {
        std::fclose(fp);
        error = "Failed to read PNG header: " + path;
        return false;
    }
    if (png_sig_cmp(header, 0, sizeof(header)) != 0) {
        std::fclose(fp);
        error = "File is not a PNG: " + path;
        return false;
    }

    PngErrorContext ctx { &error };
    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, &ctx, png_error_handler, png_warning_handler);
    if (!png_ptr) {
        std::fclose(fp);
        error = "Failed to create PNG read struct";
        return false;
    }
    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_read_struct(&png_ptr, nullptr, nullptr);
        std::fclose(fp);
        error = "Failed to create PNG info struct";
        return false;
    }

    png_init_io(png_ptr, fp);
    png_set_sig_bytes(png_ptr, static_cast<int>(sizeof(header)));

    bool ok = decode_png(png_ptr, info_ptr, out, error);
    png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
    std::fclose(fp);
    return ok;
}

bool load_png_memory(const std::uint8_t* data, std::size_t size, ImageBuffer& out, std::string& error) {
    out = {};
    error.clear();

    if (!data || size < 8) {
        error = "PNG buffer too small";
        return false;
    }
    if (png_sig_cmp(const_cast<png_bytep>(data), 0, 8) != 0) {
        error = "Buffer is not a PNG";
        return false;
    }

    PngMemoryReader reader { data, size, 8 };
    PngErrorContext ctx { &error };
    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, &ctx, png_error_handler, png_warning_handler);
    if (!png_ptr) {
        error = "Failed to create PNG read struct";
        return false;
    }
    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_read_struct(&png_ptr, nullptr, nullptr);
        error = "Failed to create PNG info struct";
        return false;
    }

    png_set_read_fn(png_ptr, &reader, png_read_memory);
    png_set_sig_bytes(png_ptr, 8);

    bool ok = decode_png(png_ptr, info_ptr, out, error);
    png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
    return ok;
}

bool load_jpeg_file(const std::string& path, ImageBuffer& out, std::string& error) {
    out = {};
    error.clear();

    FILE* fp = std::fopen(path.c_str(), "rb");
    if (!fp) {
        error = "Unable to open JPEG file: " + path;
        return false;
    }

    jpeg_decompress_struct cinfo {};
    JpegErrorContext jerr {};
    jerr.error = &error;
    cinfo.err = jpeg_std_error(&jerr.base);
    jerr.base.error_exit = jpeg_error_handler;

    if (setjmp(jerr.jump)) {
        jpeg_destroy_decompress(&cinfo);
        std::fclose(fp);
        if (error.empty()) {
            error = "JPEG decode failed";
        }
        return false;
    }

    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, fp);
    bool ok = decode_jpeg(cinfo, out, error);
    jpeg_destroy_decompress(&cinfo);
    std::fclose(fp);
    return ok;
}

bool load_jpeg_memory(const std::uint8_t* data, std::size_t size, ImageBuffer& out, std::string& error) {
    out = {};
    error.clear();

    if (!data || size < 2) {
        error = "JPEG buffer too small";
        return false;
    }

    jpeg_decompress_struct cinfo {};
    JpegErrorContext jerr {};
    jerr.error = &error;
    cinfo.err = jpeg_std_error(&jerr.base);
    jerr.base.error_exit = jpeg_error_handler;

    if (setjmp(jerr.jump)) {
        jpeg_destroy_decompress(&cinfo);
        if (error.empty()) {
            error = "JPEG decode failed";
        }
        return false;
    }

    jpeg_create_decompress(&cinfo);
    jpeg_mem_src(&cinfo, const_cast<unsigned char*>(data), static_cast<unsigned long>(size));
    bool ok = decode_jpeg(cinfo, out, error);
    jpeg_destroy_decompress(&cinfo);
    return ok;
}

bool load_image_file(const std::string& path, ImageBuffer& out, std::string& error) {
    const auto dot = path.find_last_of('.');
    std::string ext = dot == std::string::npos ? "" : to_lower(path.substr(dot));
    if (ext == ".png") {
        return load_png_file(path, out, error);
    }
    if (ext == ".jpg" || ext == ".jpeg") {
        return load_jpeg_file(path, out, error);
    }
    error = "Unsupported image extension: " + path;
    return false;
}

bool load_image_memory(const std::uint8_t* data, std::size_t size, ImageBuffer& out, std::string& error) {
    if (has_png_header(data, size)) {
        return load_png_memory(data, size, out, error);
    }
    if (has_jpeg_header(data, size)) {
        return load_jpeg_memory(data, size, out, error);
    }
    error = "Unsupported image buffer";
    return false;
}
