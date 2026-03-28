#version 330 core

#include "lighting.glsl"

in vec4 theColor;
in vec3 worldPos;
in vec3 worldNormal;

uniform int unlit;
uniform int lightingViewMode;
uniform vec3 lightingViewPos;
uniform vec3 lightingViewDir;
uniform vec3 ambientLight;
uniform int dirLightCount;
uniform DirLight dirLights[MAX_DIR_LIGHTS];
uniform int pointLightCount;
uniform PointLight pointLights[MAX_POINT_LIGHTS];
uniform int spotLightCount;
uniform SpotLight spotLights[MAX_SPOT_LIGHTS];

out vec4 fragColor;

void main () {
    if (unlit == 1) {
        fragColor = theColor;
        return;
    }
    vec3 normal = normalize(worldNormal);
    vec3 viewDir = ResolveLightingViewDir(lightingViewMode,
                                          lightingViewPos,
                                          lightingViewDir,
                                          worldPos);
    vec3 light = ambientLight;
    light += CalcDirLights(dirLights, dirLightCount, normal, viewDir);
    light += CalcPointLights(pointLights, pointLightCount, normal, worldPos, viewDir);
    light += CalcSpotLights(spotLights, spotLightCount, normal, worldPos, viewDir);
    fragColor = vec4(light, 1.0f) * theColor;
}
