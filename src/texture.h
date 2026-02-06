#ifndef TEXTURE_H
#define TEXTURE_H

#ifdef __linux__
#include <SDL2/SDL.h>
#elif _WIN32

#include <SDL.h>

#endif

#include <epoxy/gl.h>
#include <GL/gl.h>

#include <memory>
#include <cstddef>
#include <cstdint>
#include <vector>
#include <string>

// Texture2D is able to store and configure a texture in OpenGL.
// It also hosts utility functions for easy management.
class Texture2D {
public:
    // Holds the id of the texture object, used for all texture operations to reference to this specific texture
    GLuint id { 0 };

    // Hold loaded data
    using PixelDeleter = void(*)(void*);
    using PixelBuffer = std::unique_ptr<std::uint8_t[], PixelDeleter>;

    PixelBuffer image_data { nullptr, nullptr };
    std::size_t image_size { 0 };
    bool ready { false };

    // Texture image dimensions
    // Width and height of loaded image in pixels
    int width { 0 };
    int height { 0 };

    int n { 0 };

    // Texture Format
    GLuint internalFormat { GL_RGB }; // Format of texture object
    GLuint imageFormat { GL_RGB };    // Format of loaded image

    // Texture configuration
    GLint wrapS { GL_CLAMP_TO_EDGE };     // Wrapping mode on S axis
    GLint wrapT { GL_CLAMP_TO_EDGE };     // Wrapping mode on T axis
    GLfloat filterMin { GL_LINEAR }; // Filtering mode if texture pixels < screen pixels
    GLfloat filterMax { GL_LINEAR }; // Filtering mode if texture pixels > screen pixels

    // Constructor (sets default texture modes)
    Texture2D();

    // Load texture file
    void load(const std::string& filename);
    void load_from_pixels(int w,
                          int h,
                          int channels,
                          PixelBuffer&& pixels,
                          std::size_t byte_count,
                          bool already_flipped = false);

    // Generates texture from image data
    void generate();
    void begin_upload();
    bool upload_rows(int rows_per_call);

    // Binds the texture as the current active GL_TEXTURE_2D texture object
    void setActive() const;

    bool upload_in_progress { false };
    int upload_row { 0 };
};

class TextureCubemap {
public:
    GLuint id { 0 };
    bool ready { false };
    using PixelDeleter = void(*)(void*);
    using PixelBuffer = std::unique_ptr<std::uint8_t[], PixelDeleter>;
    PixelBuffer image_data { nullptr, nullptr };
    std::size_t image_size { 0 };
    int width { 0 };
    int height { 0 };
    int n { 0 };
    int faces { 0 };
    bool upload_in_progress { false };
    int upload_face { 0 };

    TextureCubemap();

    void loadFaces(const std::vector<std::string>& files);
    void load_from_pixels(int width,
                          int height,
                          int channels,
                          const std::uint8_t* pixels,
                          std::size_t byte_count);
    void begin_upload_from_pixels(int width,
                                  int height,
                                  int channels,
                                  PixelBuffer&& pixels,
                                  std::size_t byte_count,
                                  int face_count);
    bool upload_faces(int faces_per_call);
    void drop();
};

#endif
