#ifndef RESOURCE_MANAGER_H
#define RESOURCE_MANAGER_H

#include <map>
#include <string>
#include <unordered_map>
#include <vector>
#include <functional>

#include <epoxy/gl.h>

#include "job_system.h"
#include "audio.h"
#include "texture.h"
#include "shader.h"

// A static singleton ResourceManager class that hosts several
// functions to load Textures and Shaders. Each loaded texture
// and/or shader is also stored for future reference by string
// handles. All functions and resources are static and no
// public constructor is defined.
class ResourceManager {
public:
    ResourceManager() = delete;

    // Resource storage
    static std::map<std::string, Shader> shaders;
    static std::map<std::string, Texture2D> textures;
    static std::map<std::string, TextureCubemap> cubemaps;
    static Audio* audio;
    using ReadyCallback = std::function<void(const std::string&)>;
    struct PendingTexture {
        std::string name;
        std::string file;
        ReadyCallback callback;
    };
    struct PendingTextureBytes {
        std::string name;
        ReadyCallback callback;
    };
    struct PendingTextureUpload {
        std::string name;
        ReadyCallback callback;
    };
    struct PendingCubemap {
        std::string name;
        std::vector<std::string> files;
        ReadyCallback callback;
    };
    struct PendingCubemapUpload {
        std::string name;
        ReadyCallback callback;
    };
    struct PendingAudio {
        std::string name;
        std::string file;
        ReadyCallback callback;
    };
    static JobSystem* jobSystem;
    static std::unordered_map<uint64_t, PendingTexture> pendingTextures;
    static std::unordered_map<uint64_t, PendingTextureBytes> pendingTextureBytes;
    static std::vector<PendingTextureUpload> pendingTextureUploads;
    static std::unordered_map<uint64_t, PendingCubemap> pendingCubemaps;
    static std::vector<PendingCubemapUpload> pendingCubemapUploads;
    static std::unordered_map<uint64_t, PendingAudio> pendingAudio;

    // Loads (and generates) a shader program from file loading vertex, fragment (and geometry) shader's source code. If gShaderFile is not nullptr, it also loads a geometry shader
    static Shader
    loadShader(const std::string& name, const std::string& vertexCode, const std::string& fragmentCode, const std::string& geometryCode);

    // Retrieves a stored shader
    static Shader getShader(const std::string& name);

    // Retrieves a stored texture
    static Texture2D& getTexture(const std::string& name);
    static TextureCubemap& getCubemap(const std::string& name);

    // Properly de-allocates all loaded resources
    static void clear();

    // Loads and generates a shader from file
    static Shader loadShaderFromFile(const std::string& name, const std::string& vShaderFile, const std::string& fShaderFile,
                                     const std::string& gShaderFile = "");

    // Loads a single texture from file
    static Texture2D& loadTextureFromFile(const std::string& name, const std::string& file);
    static TextureCubemap& loadCubemapFromFiles(const std::string& name, const std::vector<std::string>& files);

    // Async texture pipeline
    static void setJobSystem(JobSystem* system);
    static void setAudio(Audio* system);
    static Texture2D& loadTextureAsync(const std::string& name, const std::string& file, ReadyCallback onReady = {});
    static Texture2D& loadTextureFromBytesAsync(const std::string& name, const std::string& bytes, bool alreadyFlipped,
                                                ReadyCallback onReady = {});
    static TextureCubemap& loadCubemapAsync(const std::string& name, const std::vector<std::string>& files, ReadyCallback onReady = {});
    static bool loadAudioAsync(const std::string& name, const std::string& file, ReadyCallback onReady = {});
    static std::size_t processTextureJobs(std::size_t maxResults = 0);
    static std::size_t processAudioJobs(std::size_t maxResults = 0);
    static void clearPending();
};

void register_texture_job_handlers(JobSystem& jobs);
void register_audio_job_handlers(JobSystem& jobs);

#endif
