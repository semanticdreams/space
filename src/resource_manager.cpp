#include "resource_manager.h"
#include "log.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <memory>

// Instantiate static variables
std::map<std::string, Texture2D> ResourceManager::textures;
std::map<std::string, Shader> ResourceManager::shaders;

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

Texture2D ResourceManager::getTexture(const std::string& name) {
    return textures[name];
}

void ResourceManager::clear() {
    // (Properly) delete all shaders
    for (const auto& iter: shaders)
        glDeleteProgram(iter.second.id);
    // (Properly) delete all textures
    for (const auto& iter: textures)
        glDeleteTextures(1, &iter.second.id);
}

Shader ResourceManager::loadShaderFromFile(const std::string& name, const std::string& vShaderFile, const std::string& fShaderFile,
                                           const std::string& gShaderFile) {
    // 1. Retrieve the vertex/fragment source code from filePath
    std::string vertexCode;
    std::string fragmentCode;
    std::string geometryCode;
    try {
        // Open files
        std::ifstream vertexShaderFile(vShaderFile);
        std::ifstream fragmentShaderFile(fShaderFile);
        std::stringstream vShaderStream, fShaderStream;
        // Read file's buffer contents into streams
        vShaderStream << vertexShaderFile.rdbuf();
        fShaderStream << fragmentShaderFile.rdbuf();
        // close file handlers
        vertexShaderFile.close();
        fragmentShaderFile.close();
        // Convert stream into string
        vertexCode = vShaderStream.str();
        fragmentCode = fShaderStream.str();
        // If geometry shader path is present, also load a geometry shader
        if (!gShaderFile.empty()) {
            std::ifstream geometryShaderFile(gShaderFile);
            std::stringstream gShaderStream;
            gShaderStream << geometryShaderFile.rdbuf();
            geometryShaderFile.close();
            geometryCode = gShaderStream.str();
        }
    }
    catch (std::exception e) {
        std::ostringstream loadError;
        std::string geomShaderFile;
        if (!gShaderFile.empty())
            geomShaderFile = gShaderFile;

        loadError << "ERROR::SHADER: Failed to read shader files " << vShaderFile << " " << fShaderFile << " "
                  << geomShaderFile << "\n"
                  << "\n -- --------------------------------------------------- -- "
                  << std::endl;
        LOG(Error) << loadError.str();
    }
    return loadShader(name, vertexCode, fragmentCode, geometryCode);
}

Texture2D ResourceManager::loadTextureFromFile(const std::string& name, const std::string& file) {
    Texture2D texture;
    texture.load(file);
    texture.generate();
    textures[name] = texture;
    return texture;
}
