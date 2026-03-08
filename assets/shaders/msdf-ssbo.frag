#version 430 core

#include "clipping.glsl"
#include "depth-bias.glsl"

in vec2 texCoord;
in vec3 worldPos;
in vec4 textColor;
flat in uint groupIndex;

out vec4 color;

uniform sampler2D msdf;
uniform float pxRange;
uniform vec3 textColorMul;
uniform float textAlpha;

layout(std430, binding = 1) readonly buffer GroupClips {
    mat4 clipMatrix[];
};

layout(std430, binding = 2) readonly buffer GroupClipIndex {
    uint groupClipIndex[];
};

layout(std430, binding = 3) readonly buffer GroupDepthOffsetIndex {
    float groupDepthOffsetIndex[];
};

float screenPxRange() {
    vec2 unitRange = vec2(pxRange) / vec2(textureSize(msdf, 0));
    vec2 screenTexSize = vec2(1.0) / fwidth(texCoord);
    return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    uint clipIndex = groupClipIndex[groupIndex];
    if (isClipped(clipMatrix[clipIndex], worldPos)) {
        discard;
    }
    vec3 msd = texture(msdf, texCoord).rgb;
    float sd = median(msd.r, msd.g, msd.b);
    float screenPxDistance = screenPxRange() * (sd - 0.5);
    float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    color = vec4(textColor.rgb * textColorMul * opacity,
                 textColor.a * textAlpha * opacity);
    float depthOffset = groupDepthOffsetIndex[groupIndex];
    gl_FragDepth = applyDepthOffset(gl_FragCoord.z, depthOffset);
}
