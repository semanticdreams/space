#version 330 core

#include "lighting.glsl"

in vec2 theUv;
in vec3 worldPos;
in vec3 worldNormal;

uniform sampler2D myTexture;
uniform vec3 viewPos;
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
    vec3 normal = normalize(worldNormal);
    vec3 viewDir = normalize(viewPos - worldPos);
    vec3 light = ambientLight;
    light += CalcDirLights(dirLights, dirLightCount, normal, viewDir);
    light += CalcPointLights(pointLights, pointLightCount, normal, worldPos, viewDir);
    light += CalcSpotLights(spotLights, spotLightCount, normal, worldPos, viewDir);
    fragColor = vec4(light, 1.0f) * baseColor;
}
