#pragma once

#include <cstdint>
#include <memory>
#include <string>

struct ImageBuffer {
    std::unique_ptr<std::uint8_t[]> pixels;
    int width { 0 };
    int height { 0 };
    int channels { 0 };
};

bool load_png_file(const std::string& path, ImageBuffer& out, std::string& error);
bool load_png_memory(const std::uint8_t* data, std::size_t size, ImageBuffer& out, std::string& error);
bool load_jpeg_file(const std::string& path, ImageBuffer& out, std::string& error);
bool load_jpeg_memory(const std::uint8_t* data, std::size_t size, ImageBuffer& out, std::string& error);
bool load_image_file(const std::string& path, ImageBuffer& out, std::string& error);
bool load_image_memory(const std::uint8_t* data, std::size_t size, ImageBuffer& out, std::string& error);
