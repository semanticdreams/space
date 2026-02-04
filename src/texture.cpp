#include <cstdint>
#include <cstddef>

#include "image_loader.h"
#include "texture.h"

#define LOG_SUBSYSTEM "texture"

#include "log.h"

namespace {

void flip_vertical(std::uint8_t* data, int width, int height, int channels) {
    int width_in_bytes = width * channels;
    int half_height = height / 2;

    for (int row = 0; row < half_height; row++) {
        std::uint8_t* top = data + row * width_in_bytes;
        std::uint8_t* bottom = data + (height - row - 1) * width_in_bytes;
        for (int col = 0; col < width_in_bytes; col++) {
            std::uint8_t temp = *top;
            *top = *bottom;
            *bottom = temp;
            ++top;
            ++bottom;
        }
    }
}

} // namespace

Texture2D::Texture2D() {
    glGenTextures(1, &id);
}

void Texture2D::load(const std::string& filename) {
    int w = 0;
    int h = 0;
    int channels = 0;
    ImageBuffer image;
    std::string error;
    if (!load_image_file(filename, image, error)) {
        LOG(Error) << "Could not load " << filename << ": " << error;
        ready = false;
        return;
    }
    w = image.width;
    h = image.height;
    channels = image.channels;
    std::size_t byteCount = static_cast<std::size_t>(w) *
                            static_cast<std::size_t>(h) *
                            static_cast<std::size_t>(channels);
    PixelBuffer buffer(image.pixels.release(), [](void* ptr) { delete[] static_cast<std::uint8_t*>(ptr); });
    load_from_pixels(w, h, channels, std::move(buffer), byteCount);
    generate();
}

void Texture2D::load_from_pixels(int w,
                                 int h,
                                 int channels,
                                 PixelBuffer&& pixels,
                                 std::size_t byte_count,
                                 bool already_flipped) {
    width = w;
    height = h;
    n = channels;
    image_data = std::move(pixels);
    image_size = byte_count;
    ready = false;
    upload_in_progress = false;
    upload_row = 0;
    if (!already_flipped && image_data && image_size > 0) {
        flip_vertical(image_data.get(), width, height, n);
    }
    if (n == 4) {
        internalFormat = GL_RGBA;
        imageFormat = GL_RGBA;
    } else {
        internalFormat = GL_RGB;
        imageFormat = GL_RGB;
    }
}

void Texture2D::generate() {
    if (!image_data || image_size == 0) {
        return;
    }
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, id);
    glTexImage2D(
            GL_TEXTURE_2D,
            0,
            internalFormat,
            width,
            height,
            0,
            imageFormat,
            GL_UNSIGNED_BYTE,
            image_data.get());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrapS);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrapT); // GL_CLAMP_TO_EDGE
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filterMin);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filterMax);
    glBindTexture(GL_TEXTURE_2D, 0);
    image_data.reset();
    image_size = 0;
    ready = true;
    upload_in_progress = false;
    upload_row = 0;
}

void Texture2D::begin_upload() {
    if (!image_data || image_size == 0) {
        return;
    }
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, id);
    glTexImage2D(
            GL_TEXTURE_2D,
            0,
            internalFormat,
            width,
            height,
            0,
            imageFormat,
            GL_UNSIGNED_BYTE,
            nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrapS);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrapT); // GL_CLAMP_TO_EDGE
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filterMin);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filterMax);
    glBindTexture(GL_TEXTURE_2D, 0);
    ready = false;
    upload_in_progress = true;
    upload_row = 0;
}

bool Texture2D::upload_rows(int rows_per_call) {
    if (!upload_in_progress || !image_data || image_size == 0) {
        return false;
    }
    int remaining = height - upload_row;
    if (remaining <= 0) {
        upload_in_progress = false;
        ready = true;
        return true;
    }
    int rows = rows_per_call < remaining ? rows_per_call : remaining;
    const std::uint8_t* row_ptr = image_data.get() +
                                  static_cast<std::size_t>(upload_row) *
                                  static_cast<std::size_t>(width) *
                                  static_cast<std::size_t>(n);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, id);
    glTexSubImage2D(
            GL_TEXTURE_2D,
            0,
            0,
            upload_row,
            width,
            rows,
            imageFormat,
            GL_UNSIGNED_BYTE,
            row_ptr);
    glBindTexture(GL_TEXTURE_2D, 0);
    upload_row += rows;
    if (upload_row >= height) {
        image_data.reset();
        image_size = 0;
        ready = true;
        upload_in_progress = false;
        upload_row = 0;
        return true;
    }
    return false;
}

void Texture2D::setActive() const {
    glBindTexture(GL_TEXTURE_2D, id);
}

TextureCubemap::TextureCubemap() {
    glGenTextures(1, &id);
}

void TextureCubemap::loadFaces(const std::vector<std::string>& files) {
    if (files.empty()) {
        LOG(Warning) << "Tried to load cubemap with no faces";
        return;
    }

    if (files.size() != 6) {
        LOG(Warning) << "Cubemap expected 6 faces but received " << files.size();
    }

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, id);

    for (size_t i = 0; i < files.size(); ++i) {
        int width = 0;
        int height = 0;
        int channels = 0;
        ImageBuffer image;
        std::string error;
        if (!load_image_file(files[i], image, error)) {
            LOG(Error) << "Could not load cubemap face " << files[i] << ": " << error;
            continue;
        }
        width = image.width;
        height = image.height;
        channels = image.channels;

        GLenum format = channels == 4 ? GL_RGBA : GL_RGB;
        glTexImage2D(
                GL_TEXTURE_CUBE_MAP_POSITIVE_X + static_cast<GLenum>(i),
                0,
                format,
                width,
                height,
                0,
                format,
                GL_UNSIGNED_BYTE,
                image.pixels.get());
    }

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    ready = true;
}

void TextureCubemap::load_from_pixels(int width,
                                      int height,
                                      int channels,
                                      const std::uint8_t* pixels,
                                      std::size_t byte_count) {
    if (id == 0) {
        glGenTextures(1, &id);
    }
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, id);

    std::size_t faceSize = static_cast<std::size_t>(width) *
                           static_cast<std::size_t>(height) *
                           static_cast<std::size_t>(channels);
    std::size_t faces = faceSize == 0 ? 0 : (byte_count / faceSize);
    GLenum format = channels == 4 ? GL_RGBA : GL_RGB;

    for (std::size_t i = 0; i < faces; ++i) {
        const std::uint8_t* data = pixels + (i * faceSize);
        glTexImage2D(
                GL_TEXTURE_CUBE_MAP_POSITIVE_X + static_cast<GLenum>(i),
                0,
                format,
                width,
                height,
                0,
                format,
                GL_UNSIGNED_BYTE,
                data);
    }

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    ready = true;
}

void TextureCubemap::begin_upload_from_pixels(int width,
                                              int height,
                                              int channels,
                                              PixelBuffer&& pixels,
                                              std::size_t byte_count,
                                              int face_count) {
    if (id == 0) {
        glGenTextures(1, &id);
    }
    this->width = width;
    this->height = height;
    this->n = channels;
    faces = face_count;
    image_data = std::move(pixels);
    image_size = byte_count;
    upload_face = 0;
    upload_in_progress = true;
    ready = false;

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, id);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
}

bool TextureCubemap::upload_faces(int faces_per_call) {
    if (!upload_in_progress || !image_data || image_size == 0 || faces <= 0) {
        return false;
    }
    std::size_t face_size = static_cast<std::size_t>(width) *
                            static_cast<std::size_t>(height) *
                            static_cast<std::size_t>(n);
    if (face_size == 0 || image_size < face_size * static_cast<std::size_t>(faces)) {
        upload_in_progress = false;
        ready = false;
        image_data.reset();
        image_size = 0;
        return false;
    }
    int remaining = faces - upload_face;
    if (remaining <= 0) {
        upload_in_progress = false;
        ready = true;
        return true;
    }
    int faces_to_upload = faces_per_call < remaining ? faces_per_call : remaining;
    GLenum format = n == 4 ? GL_RGBA : GL_RGB;

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, id);
    for (int i = 0; i < faces_to_upload; ++i) {
        int face_index = upload_face + i;
        const std::uint8_t* data = image_data.get() + (face_size * static_cast<std::size_t>(face_index));
        glTexImage2D(
                GL_TEXTURE_CUBE_MAP_POSITIVE_X + static_cast<GLenum>(face_index),
                0,
                format,
                width,
                height,
                0,
                format,
                GL_UNSIGNED_BYTE,
                data);
    }
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    upload_face += faces_to_upload;
    if (upload_face >= faces) {
        image_data.reset();
        image_size = 0;
        upload_face = 0;
        upload_in_progress = false;
        ready = true;
        return true;
    }
    return false;
}

void TextureCubemap::drop() {
    if (id != 0) {
        glDeleteTextures(1, &id);
        id = 0;
    }
    image_data.reset();
    image_size = 0;
    upload_in_progress = false;
    upload_face = 0;
    ready = false;
}
