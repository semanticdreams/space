#version 330 core

#include "lighting.glsl"

in vec2 theUv;
in vec3 worldPos;
in vec3 worldNormal;

uniform sampler2D myTexture;
uniform int unlit;
uniform int forceOpaque;
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
    vec4 baseColor = texture(myTexture, vec2(theUv.x, 1-theUv.y));
    if (forceOpaque == 1) {
        baseColor.a = 1.0;
    }
    if (unlit == 1) {
        fragColor = baseColor;
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
    fragColor = vec4(light, 1.0f) * baseColor;
}
