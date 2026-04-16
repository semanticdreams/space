#version 430 core

#include "clipping.glsl"
#include "depth-bias.glsl"
#include "lighting.glsl"

smooth in vec4 theColor;
smooth in vec3 worldPos;
smooth in vec3 worldNormal;
flat in float depth_offset_index;
flat in uint clipGroup;
out vec4 fragColor;

uniform int lightingViewMode;
uniform vec3 lightingViewPos;
uniform vec3 lightingViewDir;
uniform int unlit;
uniform vec3 ambientLight;
uniform int dirLightCount;
uniform DirLight dirLights[MAX_DIR_LIGHTS];
uniform int pointLightCount;
uniform PointLight pointLights[MAX_POINT_LIGHTS];
uniform int spotLightCount;
uniform SpotLight spotLights[MAX_SPOT_LIGHTS];

layout(std430, binding = 0) readonly buffer QuadClipGroups {
    mat4 clipModel[];
};

void main()
{
    if (theColor.a <= 0.0) {
        discard;
    }

    if (isClipped(clipModel[clipGroup], worldPos)) {
        discard;
    }

    vec3 normal = normalize(worldNormal);
    vec3 viewDir = ResolveLightingViewDir(lightingViewMode,
                                          lightingViewPos,
                                          lightingViewDir,
                                          worldPos);
    if (unlit != 0) {
        fragColor = theColor;
    } else {
        vec3 lightingViewDir = viewDir;
        vec3 light = ambientLight;
        light += CalcDirLights(dirLights, dirLightCount, normal, lightingViewDir);
        light += CalcPointLights(pointLights, pointLightCount, normal, worldPos, lightingViewDir);
        light += CalcSpotLights(spotLights, spotLightCount, normal, worldPos, lightingViewDir);
        fragColor = vec4(light, 1.0f) * theColor;
    }
    gl_FragDepth = applyDepthOffset(gl_FragCoord.z, depth_offset_index);
}
