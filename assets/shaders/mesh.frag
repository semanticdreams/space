#version 330 core

#include "lighting.glsl"

in vec2 theUv;
in vec3 worldPos;
in vec3 worldNormal;

uniform sampler2D myTexture;
uniform vec3 viewPos;
uniform DirLight dirLight;

out vec4 fragColor;

void main () {
    vec4 baseColor = texture(myTexture, vec2(theUv.x, 1-theUv.y));
    vec3 normal = normalize(worldNormal);
    vec3 viewDir = normalize(viewPos - worldPos);
    vec3 light = CalcDirLight(dirLight, normal, viewDir);
    fragColor = vec4(light, 1.0f) * baseColor;
}
