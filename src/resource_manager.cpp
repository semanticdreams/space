#include "resource_manager.h"

#define LOG_SUBSYSTEM "resources"

#include "log.h"
#include "job_system.h"
#include "image_loader.h"
#include <AL/al.h>

#include <algorithm>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <vector>
#include <utility>

namespace fs = std::filesystem;

namespace {

std::string trim(const std::string& value) {
    const char* whitespace = " \t\n\r";
    const auto start = value.find_first_not_of(whitespace);
    if (start == std::string::npos) {
        return "";
    }
    const auto end = value.find_last_not_of(whitespace);
    return value.substr(start, end - start + 1);
}

fs::path canonicalize(const fs::path& path) {
    std::error_code ec;
    fs::path resolved = fs::weakly_canonical(path, ec);
    if (ec) {
        resolved = fs::absolute(path);
    }
    return resolved;
}

std::string parseIncludeTarget(const std::string& line) {
    const auto start = line.find_first_of("\"><");
    if (start == std::string::npos) {
        throw std::runtime_error("Malformed #include directive: missing opening quote");
    }
    const char openChar = line[start];
    const char closeChar = openChar == '<' ? '>' : '"';
    const auto end = line.find(closeChar, start + 1);
    if (end == std::string::npos || end <= start + 1) {
        throw std::runtime_error("Malformed #include directive: missing closing quote");
    }
    return line.substr(start + 1, end - start - 1);
}

class IncludeStackGuard {
public:
    IncludeStackGuard(std::vector<fs::path>& stack, const fs::path& entry)
        : stack(stack) {
        stack.push_back(entry);
    }

    ~IncludeStackGuard() {
        stack.pop_back();
    }

private:
    std::vector<fs::path>& stack;
};

std::string preprocessShaderFileRecursive(const fs::path& filePath, std::vector<fs::path>& includeStack) {
    fs::path resolvedPath = canonicalize(filePath);
    if (!fs::exists(resolvedPath)) {
        throw std::runtime_error("Shader file not found: " + resolvedPath.string());
    }

    if (std::find(includeStack.begin(), includeStack.end(), resolvedPath) != includeStack.end()) {
        std::ostringstream oss;
        oss << "Circular shader include detected at " << resolvedPath;
        throw std::runtime_error(oss.str());
    }

    IncludeStackGuard guard(includeStack, resolvedPath);

    std::ifstream shaderFile(resolvedPath);
    if (!shaderFile.is_open()) {
        throw std::runtime_error("Unable to open shader file: " + resolvedPath.string());
    }

    std::stringstream processed;
    std::string line;
    while (std::getline(shaderFile, line)) {
        std::string trimmed = trim(line);
        if (trimmed.rfind("#include", 0) == 0) {
            std::string includeTarget = parseIncludeTarget(trimmed);
            fs::path includePath(includeTarget);
            if (!includePath.is_absolute()) {
                includePath = resolvedPath.parent_path() / includePath;
            }
            processed << preprocessShaderFileRecursive(includePath, includeStack);
        }
        else {
            processed << line << '\n';
        }
    }

    return processed.str();
}

std::string preprocessShaderFile(const fs::path& filePath) {
    std::vector<fs::path> includeStack;
    return preprocessShaderFileRecursive(filePath, includeStack);
}

JobSystem::NativePayload decode_image_file(const std::string& file,
                                           int& width,
                                           int& height,
                                           int& channels) {
    ImageBuffer image;
    std::string error;
    if (!load_image_file(file, image, error)) {
        return {};
    }
    width = image.width;
    height = image.height;
    channels = image.channels;
    std::size_t size = static_cast<std::size_t>(width) *
                       static_cast<std::size_t>(height) *
                       static_cast<std::size_t>(channels);
    return JobSystem::NativePayload::from_array(std::move(image.pixels), size);
}

void flip_vertical_buffer(std::uint8_t* data, int width, int height, int channels) {
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

// Provided by audio.cpp
extern bool loadWavFile(const std::string& filepath,
                        std::unique_ptr<std::uint8_t[]>& outData,
                        std::size_t& outSize,
                        ALenum& format,
                        ALsizei& freq);

// Instantiate static variables
std::map<std::string, Texture2D> ResourceManager::textures;
std::map<std::string, Shader> ResourceManager::shaders;
std::map<std::string, TextureCubemap> ResourceManager::cubemaps;
JobSystem* ResourceManager::jobSystem = nullptr;
Audio* ResourceManager::audio = nullptr;
std::unordered_map<uint64_t, ResourceManager::PendingTexture> ResourceManager::pendingTextures;
std::unordered_map<uint64_t, ResourceManager::PendingTextureBytes> ResourceManager::pendingTextureBytes;
std::vector<ResourceManager::PendingTextureUpload> ResourceManager::pendingTextureUploads;
std::unordered_map<uint64_t, ResourceManager::PendingCubemap> ResourceManager::pendingCubemaps;
std::vector<ResourceManager::PendingCubemapUpload> ResourceManager::pendingCubemapUploads;
std::unordered_map<uint64_t, ResourceManager::PendingAudio> ResourceManager::pendingAudio;

Shader ResourceManager::loadShader(const std::string& name, const std::string& vertexCode, const std::string& fragmentCode,
                                   const std::string& geometryCode) {
    const GLchar* vShaderCode = vertexCode.c_str();
    const GLchar* fShaderCode = fragmentCode.c_str();
    const GLchar* gShaderCode = !geometryCode.empty() ? geometryCode.c_str() : nullptr;
    Shader shader {};
    shader.compile(vShaderCode, fShaderCode, gShaderCode);
    shaders[name] = shader;
    return shader;
}

Shader ResourceManager::getShader(const std::string& name) {
    return shaders[name];
}

Texture2D& ResourceManager::getTexture(const std::string& name) {
    return textures[name];
}

TextureCubemap& ResourceManager::getCubemap(const std::string& name) {
    return cubemaps[name];
}

void ResourceManager::clear() {
    // (Properly) delete all shaders
    for (const auto& iter: shaders)
        glDeleteProgram(iter.second.id);
    // (Properly) delete all textures
    for (const auto& iter: textures)
        glDeleteTextures(1, &iter.second.id);
    for (const auto& iter: cubemaps)
        glDeleteTextures(1, &iter.second.id);
    shaders.clear();
    textures.clear();
    cubemaps.clear();
    clearPending();
}

Shader ResourceManager::loadShaderFromFile(const std::string& name, const std::string& vShaderFile, const std::string& fShaderFile,
                                           const std::string& gShaderFile) {
    // 1. Retrieve the vertex/fragment source code from filePath
    std::string vertexCode;
    std::string fragmentCode;
    std::string geometryCode;
    try {
        vertexCode = preprocessShaderFile(vShaderFile);
        fragmentCode = preprocessShaderFile(fShaderFile);
        if (!gShaderFile.empty()) {
            geometryCode = preprocessShaderFile(gShaderFile);
        }
    }
    catch (const std::exception& e) {
        std::ostringstream loadError;
        std::string geomShaderFile;
        if (!gShaderFile.empty())
            geomShaderFile = gShaderFile;

        loadError << "ERROR::SHADER: Failed to read shader files " << vShaderFile << " " << fShaderFile << " "
                  << geomShaderFile << "\n"
                  << "\n -- --------------------------------------------------- -- " << e.what() << std::endl;
        LOG(Error) << loadError.str();
    }
    return loadShader(name, vertexCode, fragmentCode, geometryCode);
}

Texture2D& ResourceManager::loadTextureFromFile(const std::string& name, const std::string& file) {
    Texture2D& texture = textures[name];
    texture.load(file);
    texture.generate();
    return texture;
}

TextureCubemap& ResourceManager::loadCubemapFromFiles(const std::string& name, const std::vector<std::string>& files) {
    TextureCubemap& cubemap = cubemaps[name];
    cubemap.loadFaces(files);
    cubemap.ready = true;
    return cubemap;
}

void ResourceManager::setJobSystem(JobSystem* system) {
    jobSystem = system;
}

void ResourceManager::setAudio(Audio* system) {
    audio = system;
}

Texture2D& ResourceManager::loadTextureAsync(const std::string& name, const std::string& file, ReadyCallback onReady) {
    if (!jobSystem) {
        throw std::runtime_error("Job system is not configured for ResourceManager");
    }

    Texture2D& texture = textures[name];
    texture.ready = false;

    uint64_t jobId = jobSystem->submit("load_texture", file);
    pendingTextures[jobId] = PendingTexture { name, file, std::move(onReady) };
    return texture;
}

Texture2D& ResourceManager::loadTextureFromBytesAsync(const std::string& name,
                                                      const std::string& bytes,
                                                      bool alreadyFlipped,
                                                      ReadyCallback onReady) {
    if (!jobSystem) {
        throw std::runtime_error("Job system is not configured for ResourceManager");
    }

    Texture2D& texture = textures[name];
    texture.ready = false;

    std::string payload;
    payload.reserve(bytes.size() + 1);
    payload.push_back(alreadyFlipped ? static_cast<char>(1) : static_cast<char>(0));
    payload.append(bytes);

    uint64_t jobId = jobSystem->submit("decode_texture_bytes", payload);
    pendingTextureBytes[jobId] = PendingTextureBytes { name, std::move(onReady) };
    return texture;
}

TextureCubemap& ResourceManager::loadCubemapAsync(const std::string& name, const std::vector<std::string>& files,
                                                  ReadyCallback onReady) {
    if (!jobSystem) {
        throw std::runtime_error("Job system is not configured for ResourceManager");
    }
    TextureCubemap& cubemap = cubemaps[name];
    cubemap.ready = false;

    std::ostringstream payload;
    for (std::size_t i = 0; i < files.size(); ++i) {
        payload << files[i];
        if (i + 1 < files.size()) {
            payload << "\n";
        }
    }

    uint64_t jobId = jobSystem->submit("load_cubemap", payload.str());
    pendingCubemaps[jobId] = PendingCubemap { name, files, std::move(onReady) };
    return cubemap;
}

bool ResourceManager::loadAudioAsync(const std::string& name, const std::string& file, ReadyCallback onReady) {
    if (!jobSystem) {
        return false;
    }
    uint64_t jobId = jobSystem->submit("load_audio", file);
    pendingAudio[jobId] = PendingAudio { name, file, std::move(onReady) };
    return true;
}

std::size_t ResourceManager::processTextureJobs(std::size_t maxResults) {
    if (!jobSystem) {
        return 0;
    }

    const std::size_t decodeUploadBudget = 2;
    const std::size_t uploadTextureBudget = 2;
    const int uploadRowsPerTexture = 64;
    const std::size_t uploadCubemapBudget = 1;
    const int uploadFacesPerCubemap = 1;
    std::vector<JobSystem::JobResult> results =
        jobSystem->poll_kind_owner("load_texture", JobSystem::JobOwner::Engine, maxResults);
    std::size_t applied = 0;

    for (auto& res : results) {
        auto it = pendingTextures.find(res.id);
        if (it == pendingTextures.end()) {
            LOG(Warning) << "Received texture job result with no pending entry: " << res.id;
            continue;
        }

        PendingTexture pending = std::move(it->second);
        pendingTextures.erase(it);

        if (!res.ok) {
            LOG(Error) << "Failed to load texture '" << pending.name << "': " << res.error;
            continue;
        }

        auto* pixelsPtr = static_cast<std::uint8_t*>(res.payload.data);
        const std::size_t expectedBytes = static_cast<std::size_t>(res.aux_a) *
                                          static_cast<std::size_t>(res.aux_b) *
                                          static_cast<std::size_t>(res.aux_c);
        if (!pixelsPtr || !res.payload.owner || res.payload.size_bytes < expectedBytes ||
            res.aux_a <= 0 || res.aux_b <= 0 || res.aux_c <= 0) {
            LOG(Error) << "Texture job returned invalid data for '" << pending.name << "'";
            continue;
        }

        Texture2D& texture = textures[pending.name];
        Texture2D::PixelBuffer buffer(pixelsPtr, res.payload.owner.get_deleter());
        res.payload.owner.release();
        texture.load_from_pixels(res.aux_a, res.aux_b, res.aux_c, std::move(buffer), expectedBytes, true);
        texture.generate();
        if (pending.callback) {
            pending.callback(pending.name);
        }
        applied++;
    }

    std::size_t decodeMaxResults = maxResults == 0 ? decodeUploadBudget
                                                   : std::min(maxResults, decodeUploadBudget);
    std::vector<JobSystem::JobResult> decodeResults =
        jobSystem->poll_kind_owner("decode_texture_bytes", JobSystem::JobOwner::Engine, decodeMaxResults);
    for (auto& res : decodeResults) {
        auto it = pendingTextureBytes.find(res.id);
        if (it == pendingTextureBytes.end()) {
            LOG(Warning) << "Received texture decode job result with no pending entry: " << res.id;
            continue;
        }

        PendingTextureBytes pending = std::move(it->second);
        pendingTextureBytes.erase(it);

        if (!res.ok) {
            LOG(Error) << "Failed to decode texture bytes for '" << pending.name << "': " << res.error;
            continue;
        }

        auto* pixelsPtr = static_cast<std::uint8_t*>(res.payload.data);
        const std::size_t expectedBytes = static_cast<std::size_t>(res.aux_a) *
                                          static_cast<std::size_t>(res.aux_b) *
                                          static_cast<std::size_t>(res.aux_c);
        if (!pixelsPtr || !res.payload.owner || res.payload.size_bytes < expectedBytes ||
            res.aux_a <= 0 || res.aux_b <= 0 || res.aux_c <= 0) {
            LOG(Error) << "Texture decode job returned invalid data for '" << pending.name << "'";
            continue;
        }

        Texture2D& texture = textures[pending.name];
        Texture2D::PixelBuffer buffer(pixelsPtr, res.payload.owner.get_deleter());
        res.payload.owner.release();
        texture.load_from_pixels(res.aux_a, res.aux_b, res.aux_c, std::move(buffer), expectedBytes, true);
        texture.begin_upload();
        pendingTextureUploads.push_back(PendingTextureUpload { pending.name, std::move(pending.callback) });
    }

    if (!pendingTextureUploads.empty()) {
        std::size_t uploadCount = 0;
        auto it = pendingTextureUploads.begin();
        while (it != pendingTextureUploads.end() && uploadCount < uploadTextureBudget) {
            Texture2D& texture = textures[it->name];
            bool done = texture.upload_rows(uploadRowsPerTexture);
            if (done) {
                if (it->callback) {
                    it->callback(it->name);
                }
                it = pendingTextureUploads.erase(it);
            } else {
                ++it;
            }
            uploadCount++;
            applied++;
        }
    }

    std::vector<JobSystem::JobResult> cubemapResults =
        jobSystem->poll_kind_owner("load_cubemap", JobSystem::JobOwner::Engine, maxResults);
    for (auto& res : cubemapResults) {
        auto it = pendingCubemaps.find(res.id);
        if (it == pendingCubemaps.end()) {
            LOG(Warning) << "Received cubemap job result with no pending entry: " << res.id;
            continue;
        }
        PendingCubemap pending = std::move(it->second);
        pendingCubemaps.erase(it);

        if (!res.ok) {
            LOG(Error) << "Failed to load cubemap '" << pending.name << "': " << res.error;
            continue;
        }

        if (res.aux_a <= 0 || res.aux_b <= 0 || res.aux_c <= 0 || res.aux_d <= 0) {
            LOG(Error) << "Cubemap job returned invalid dimensions for '" << pending.name << "'";
            continue;
        }

        std::size_t faceSize = static_cast<std::size_t>(res.aux_a) *
                               static_cast<std::size_t>(res.aux_b) *
                               static_cast<std::size_t>(res.aux_c);
        std::size_t expectedSize = faceSize * static_cast<std::size_t>(res.aux_d);
        auto* pixelsPtr = static_cast<std::uint8_t*>(res.payload.data);
        if (!pixelsPtr || !res.payload.owner || res.payload.size_bytes < expectedSize) {
            LOG(Error) << "Cubemap job returned insufficient data for '" << pending.name << "'";
            continue;
        }

        TextureCubemap& cubemap = cubemaps[pending.name];
        TextureCubemap::PixelBuffer buffer(pixelsPtr, res.payload.owner.get_deleter());
        res.payload.owner.release();
        cubemap.begin_upload_from_pixels(res.aux_a, res.aux_b, res.aux_c, std::move(buffer),
                                         res.payload.size_bytes, res.aux_d);
        pendingCubemapUploads.push_back(PendingCubemapUpload { pending.name, std::move(pending.callback) });
        applied++;
    }

    if (!pendingCubemapUploads.empty()) {
        std::size_t uploadCount = 0;
        auto it = pendingCubemapUploads.begin();
        while (it != pendingCubemapUploads.end() && uploadCount < uploadCubemapBudget) {
            TextureCubemap& cubemap = cubemaps[it->name];
            bool done = cubemap.upload_faces(uploadFacesPerCubemap);
            if (done) {
                if (it->callback) {
                    it->callback(it->name);
                }
                it = pendingCubemapUploads.erase(it);
            } else {
                ++it;
            }
            uploadCount++;
            applied++;
        }
    }

    return applied;
}

std::size_t ResourceManager::processAudioJobs(std::size_t maxResults) {
    if (!jobSystem || !audio) {
        return 0;
    }

    std::vector<JobSystem::JobResult> results =
        jobSystem->poll_kind_owner("load_audio", JobSystem::JobOwner::Engine, maxResults);
    std::size_t applied = 0;

    for (auto& res : results) {
        auto it = pendingAudio.find(res.id);
        if (it == pendingAudio.end()) {
            LOG(Warning) << "Received audio job result with no pending entry: " << res.id;
            continue;
        }
        PendingAudio pending = std::move(it->second);
        pendingAudio.erase(it);

        if (!res.ok) {
            LOG(Error) << "Failed to load audio '" << pending.name << "': " << res.error;
            continue;
        }

        auto* pcmPtr = static_cast<std::uint8_t*>(res.payload.data);
        if (!pcmPtr || res.payload.size_bytes == 0 || res.aux_a == 0 || res.aux_b == 0) {
            LOG(Error) << "Audio job returned invalid data for '" << pending.name << "'";
            continue;
        }

        ALenum format = static_cast<ALenum>(res.aux_a);
        ALsizei freq = static_cast<ALsizei>(res.aux_b);
        ALuint buffer = audio->createBufferFromPcm(pending.name, pcmPtr, res.payload.size_bytes, format, freq);
        if (buffer != 0) {
            applied++;
            if (pending.callback) {
                pending.callback(pending.name);
            }
        }
    }
    return applied;
}

void ResourceManager::clearPending() {
    pendingTextures.clear();
    pendingTextureBytes.clear();
    pendingTextureUploads.clear();
    pendingCubemaps.clear();
    pendingCubemapUploads.clear();
    pendingAudio.clear();
}

void register_texture_job_handlers(JobSystem& jobs) {
    jobs.register_handler("load_texture",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              int width = 0;
                              int height = 0;
                              int channels = 0;
                              JobSystem::NativePayload pixels = decode_image_file(req.payload, width, height, channels);
                              if (!pixels.data) {
                                  JobSystem::JobResult result {};
                                  result.id = req.id;
                                  result.kind = req.kind;
                                  result.ok = false;
                                  result.error = "Failed to load texture: " + req.payload;
                                  return result;
                              }

                              flip_vertical_buffer(static_cast<std::uint8_t*>(pixels.data), width, height, channels);

                              JobSystem::JobResult result {};
                              result.id = req.id;
                              result.kind = req.kind;
                              result.ok = true;
                              result.payload = std::move(pixels);
                              result.aux_a = width;
                              result.aux_b = height;
                              result.aux_c = channels;
                              return result;
                          });

    jobs.register_handler("decode_texture_bytes",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              JobSystem::JobResult result {};
                              result.id = req.id;
                              result.kind = req.kind;
                              if (req.payload.size() <= 1) {
                                  result.ok = false;
                                  result.error = "No image bytes provided for texture decode";
                                  return result;
                              }

                              const auto* raw = reinterpret_cast<const std::uint8_t*>(req.payload.data());
                              bool alreadyFlipped = raw[0] != 0;
                              const std::uint8_t* data_ptr = raw + 1;
                              std::size_t data_size = req.payload.size() - 1;
                              int width = 0;
                              int height = 0;
                              int channels = 0;
                              ImageBuffer image;
                              std::string error;
                              if (!load_image_memory(data_ptr, data_size, image, error)) {
                                  result.ok = false;
                                  result.error = "Failed to decode texture bytes: " + error;
                                  return result;
                              }
                              width = image.width;
                              height = image.height;
                              channels = image.channels;

                              if (!alreadyFlipped) {
                                  flip_vertical_buffer(image.pixels.get(), width, height, channels);
                              }

                              std::size_t size = static_cast<std::size_t>(width) *
                                                 static_cast<std::size_t>(height) *
                                                 static_cast<std::size_t>(channels);
                              result.ok = true;
                              result.payload = JobSystem::NativePayload::from_array(std::move(image.pixels), size);
                              result.aux_a = width;
                              result.aux_b = height;
                              result.aux_c = channels;
                              return result;
                          });

    jobs.register_handler("load_cubemap",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              std::vector<std::string> files;
                              std::istringstream stream(req.payload);
                              std::string line;
                              while (std::getline(stream, line)) {
                                  if (!line.empty()) {
                                      files.push_back(line);
                                  }
                              }
                              if (files.empty()) {
                                  JobSystem::JobResult result {};
                                  result.id = req.id;
                                  result.kind = req.kind;
                                  result.ok = false;
                                  result.error = "No files provided for cubemap";
                                  return result;
                              }

                              int width = 0;
                              int height = 0;
                              int channels = 0;
                              std::size_t bytesPerFace = 0;
                              std::size_t totalBytes = 0;
                              std::unique_ptr<std::uint8_t[]> combined;

                              for (std::size_t i = 0; i < files.size(); ++i) {
                                  int w = 0;
                                  int h = 0;
                                  int c = 0;
                                  JobSystem::NativePayload pixels = decode_image_file(files[i], w, h, c);
                                  if (!pixels.data) {
                                      JobSystem::JobResult result {};
                                      result.id = req.id;
                                      result.kind = req.kind;
                                      result.ok = false;
                                      result.error = "Failed to load cubemap face: " + files[i];
                                      return result;
                                  }
                                  if (i == 0) {
                                      width = w;
                                      height = h;
                                      channels = c;
                                      bytesPerFace = static_cast<std::size_t>(width) *
                                                     static_cast<std::size_t>(height) *
                                                     static_cast<std::size_t>(channels);
                                      totalBytes = bytesPerFace * files.size();
                                      combined = std::make_unique<std::uint8_t[]>(totalBytes);
                                  } else {
                                      if (w != width || h != height || c != channels) {
                                          JobSystem::JobResult result {};
                                          result.id = req.id;
                                          result.kind = req.kind;
                                          result.ok = false;
                                          result.error = "Cubemap faces must share dimensions and channels";
                                          return result;
                                      }
                                  }
                                  std::uint8_t* faceData = static_cast<std::uint8_t*>(pixels.data);
                                  std::memcpy(combined.get() + (i * bytesPerFace), faceData, bytesPerFace);
                              }

                              JobSystem::JobResult result {};
                              result.id = req.id;
                              result.kind = req.kind;
                              result.ok = true;
                              result.payload = JobSystem::NativePayload::from_array(std::move(combined), totalBytes);
                              result.aux_a = width;
                              result.aux_b = height;
                              result.aux_c = channels;
                              result.aux_d = static_cast<int>(files.size());
                              return result;
                          });
}

void register_audio_job_handlers(JobSystem& jobs) {
    jobs.register_handler("load_audio",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              std::unique_ptr<std::uint8_t[]> wavData;
                              std::size_t wavSize = 0;
                              ALenum wavFormat = AL_NONE;
                              ALsizei wavFreq = 0;
                              if (!loadWavFile(req.payload, wavData, wavSize, wavFormat, wavFreq)) {
                                  JobSystem::JobResult result {};
                                  result.id = req.id;
                                  result.kind = req.kind;
                                  result.ok = false;
                                  result.error = "Failed to load audio: " + req.payload;
                                  return result;
                              }
                              JobSystem::JobResult result {};
                              result.id = req.id;
                              result.kind = req.kind;
                              result.ok = true;
                              result.payload = JobSystem::NativePayload::from_array(std::move(wavData), wavSize);
                              result.aux_a = static_cast<int>(wavFormat);
                              result.aux_b = static_cast<int>(wavFreq);
                              return result;
                          });
}
