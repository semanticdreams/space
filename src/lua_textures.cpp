#include <cstdint>
#include <cstring>
#include <memory>
#include <optional>
#include <sol/sol.hpp>
#include <string>
#include <utility>
#include <stdexcept>

#include "image_loader.h"
#include "lua_callbacks.h"
#include "resource_manager.h"
#include "texture.h"

Texture2D& lua_load_texture(const std::string& name, const std::string& file) {
    return ResourceManager::loadTextureFromFile(name, file);
}

Texture2D& lua_load_texture_from_bytes(const std::string& name, const std::string& bytes, bool already_flipped = false) {
    int width = 0;
    int height = 0;
    int channels = 0;
    const auto* data_ptr = reinterpret_cast<const std::uint8_t*>(bytes.data());
    const std::size_t data_size = bytes.size();
    ImageBuffer image;
    std::string error;
    if (!load_image_memory(data_ptr, data_size, image, error)) {
        throw std::runtime_error("Failed to decode texture bytes: " + error);
    }
    width = image.width;
    height = image.height;
    channels = image.channels;

    Texture2D& texture = ResourceManager::textures[name];
    const std::size_t byte_count = static_cast<std::size_t>(width) *
                                   static_cast<std::size_t>(height) *
                                   static_cast<std::size_t>(channels);
    Texture2D::PixelBuffer buffer(image.pixels.release(),
                                  [](void* ptr) { delete[] static_cast<std::uint8_t*>(ptr); });
    texture.load_from_pixels(width, height, channels, std::move(buffer), byte_count, already_flipped);
    texture.generate();
    return texture;
}

Texture2D& lua_load_texture_from_pixels(const std::string& name,
                                        int width,
                                        int height,
                                        int channels,
                                        const std::string& bytes,
                                        bool already_flipped = false) {
    if (width <= 0 || height <= 0 || channels <= 0) {
        throw std::runtime_error("Texture pixel dimensions must be positive");
    }
    std::size_t expected = static_cast<std::size_t>(width) *
                           static_cast<std::size_t>(height) *
                           static_cast<std::size_t>(channels);
    if (bytes.size() < expected) {
        throw std::runtime_error("Texture pixel buffer is smaller than expected size");
    }

    auto pixels = std::make_unique<std::uint8_t[]>(expected);
    std::memcpy(pixels.get(), bytes.data(), expected);
    Texture2D& texture = ResourceManager::textures[name];
    Texture2D::PixelBuffer buffer(pixels.release(), [](void* ptr) { delete[] static_cast<std::uint8_t*>(ptr); });
    texture.load_from_pixels(width, height, channels, std::move(buffer), expected, already_flipped);
    texture.generate();
    return texture;
}

Texture2D& lua_load_texture_from_bytes_async(const std::string& name,
                                             const std::string& bytes,
                                             bool already_flipped = false,
                                             sol::object cb = sol::lua_nil) {
    std::optional<uint64_t> cb_id;
    if (cb.is<sol::function>()) {
        sol::function fn = cb.as<sol::function>();
        cb_id = lua_callbacks_register(fn);
    }
    ResourceManager::ReadyCallback onReady = [cb_id](const std::string&) {
        if (cb_id) {
            lua_callbacks_enqueue_value(cb_id.value(), sol::lua_nil);
        }
    };
    return ResourceManager::loadTextureFromBytesAsync(name, bytes, already_flipped, std::move(onReady));
}

Texture2D& lua_load_texture_from_bytes_async_simple(const std::string& name, const std::string& bytes) {
    return lua_load_texture_from_bytes_async(name, bytes);
}

Texture2D& lua_load_texture_from_bytes_async_flipped(const std::string& name,
                                                     const std::string& bytes,
                                                     bool already_flipped) {
    return lua_load_texture_from_bytes_async(name, bytes, already_flipped);
}

Texture2D& lua_load_texture_from_bytes_async_cb(const std::string& name,
                                                const std::string& bytes,
                                                sol::function cb) {
    return lua_load_texture_from_bytes_async(name, bytes, false, cb);
}

Texture2D& lua_load_texture_from_bytes_async_flipped_cb(const std::string& name,
                                                        const std::string& bytes,
                                                        bool already_flipped,
                                                        sol::function cb) {
    return lua_load_texture_from_bytes_async(name, bytes, already_flipped, cb);
}

Texture2D& lua_get_texture(const std::string& name) {
    return ResourceManager::getTexture(name);
}

TextureCubemap& lua_load_cubemap(sol::as_table_t<std::vector<std::string>> files) {
    static int counter = 0;
    std::string name = "__cubemap_sync_" + std::to_string(counter++);
    return ResourceManager::loadCubemapFromFiles(name, files.value());
}

TextureCubemap& lua_load_cubemap_async(sol::as_table_t<std::vector<std::string>> files, sol::object cb = sol::lua_nil) {
    static int counter = 0;
    std::string name = "__cubemap_" + std::to_string(counter++);
    std::optional<uint64_t> cb_id;
    if (cb.is<sol::function>()) {
        sol::function fn = cb.as<sol::function>();
        cb_id = lua_callbacks_register(fn);
    }
    ResourceManager::ReadyCallback onReady = [cb_id](const std::string&) {
        if (cb_id) {
            lua_callbacks_enqueue_value(cb_id.value(), sol::lua_nil);
        }
    };
    return ResourceManager::loadCubemapAsync(name, files.value(), std::move(onReady));
}

Texture2D& lua_load_texture_async(const std::string& name, const std::string& file, sol::object cb = sol::lua_nil) {
    std::optional<uint64_t> cb_id;
    if (cb.is<sol::function>()) {
        sol::function fn = cb.as<sol::function>();
        cb_id = lua_callbacks_register(fn);
    }
    ResourceManager::ReadyCallback onReady = [cb_id](const std::string&) {
        if (cb_id) {
            lua_callbacks_enqueue_value(cb_id.value(), sol::lua_nil);
        }
    };
    return ResourceManager::loadTextureAsync(name, file, std::move(onReady));
}

namespace {

sol::table create_textures_table(sol::state_view lua)
{
    // Bind the Texture2D class
    sol::table textures_table = lua.create_table();
    textures_table.new_usertype<Texture2D>("Texture2D",
        "id", &Texture2D::id,
        "width", &Texture2D::width,
        "height", &Texture2D::height,
        "n", &Texture2D::n,
        "ready", &Texture2D::ready,

        "wrapS", &Texture2D::wrapS,
        "wrapT", &Texture2D::wrapT,
        "filterMin", &Texture2D::filterMin,
        "filterMax", &Texture2D::filterMax,

        "load", &Texture2D::load,
        "generate", &Texture2D::generate,
        "setActive", &Texture2D::setActive
    );

    textures_table.new_usertype<TextureCubemap>("TextureCubemap",
        "id", &TextureCubemap::id,
        "ready", &TextureCubemap::ready,
        "load-faces", [](TextureCubemap& self, sol::as_table_t<std::vector<std::string>> files) {
            self.loadFaces(files.value());
        },
        "drop", &TextureCubemap::drop
    );

    textures_table.set_function("load-texture", &lua_load_texture);
    textures_table.set_function("load-texture-async", &lua_load_texture_async);
    textures_table.set_function("load-texture-from-bytes", &lua_load_texture_from_bytes);
    textures_table.set_function("load-texture-from-bytes-async", sol::overload(
        &lua_load_texture_from_bytes_async_simple,
        &lua_load_texture_from_bytes_async_flipped,
        &lua_load_texture_from_bytes_async_cb,
        &lua_load_texture_from_bytes_async_flipped_cb));
    textures_table.set_function("load-texture-from-pixels", &lua_load_texture_from_pixels);
    textures_table.set_function("get-texture", &lua_get_texture);
    textures_table.set_function("load-cubemap", &lua_load_cubemap);
    textures_table.set_function("load-cubemap-async", &lua_load_cubemap_async);
    return textures_table;
}

} // namespace

void lua_bind_textures(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("textures", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_textures_table(lua);
    });
}
