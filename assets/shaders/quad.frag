#version 430 core

#include "lighting.glsl"

smooth in vec4 theColor;
smooth in vec3 worldPos;
smooth in vec3 worldNormal;
flat in float depth_offset_index;
flat in uint clipGroup;
out vec4 fragColor;

const float depthStep = 1e-3;

uniform vec3 viewPos;
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
    vec4 clipPos = clipModel[clipGroup] * vec4(worldPos, 1.0);
    if (clipPos.x < 0.0 || clipPos.x > 1.0 ||
        clipPos.y < 0.0 || clipPos.y > 1.0) {
        discard;
    }

    vec3 normal = normalize(worldNormal);
    vec3 viewDir = normalize(viewPos - worldPos);
    vec3 lightingViewDir = viewDir;
    vec3 light = ambientLight;
    light += CalcDirLights(dirLights, dirLightCount, normal, lightingViewDir);
    light += CalcPointLights(pointLights, pointLightCount, normal, worldPos, lightingViewDir);
    light += CalcSpotLights(spotLights, spotLightCount, normal, worldPos, lightingViewDir);

    fragColor = vec4(light, 1.0f) * theColor;
    gl_FragDepth = max(0.0, gl_FragCoord.z - (gl_FragCoord.z * depth_offset_index * depthStep));
}
