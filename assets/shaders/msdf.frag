#version 130

#include "clipping.glsl"

in vec2 texCoord;
in vec4 fgColor;
flat in float depth_offset_index;
smooth in vec3 worldPos;

out vec4 color;

uniform sampler2D msdf;
uniform float pxRange;

const float depthStep = 1e-3;

float screenPxRange() {
    vec2 unitRange = vec2(pxRange)/vec2(textureSize(msdf, 0));
    vec2 screenTexSize = vec2(1.0)/fwidth(texCoord);
    return max(0.5*dot(unitRange, screenTexSize), 1.0);
}

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    if (isClipped(worldPos)) {
        discard;
    }
    vec3 msd = texture(msdf, texCoord).rgb;
    float sd = median(msd.r, msd.g, msd.b);
    float screenPxDistance = screenPxRange()*(sd - 0.5);
    float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    color = vec4(fgColor.rgb * opacity, opacity);
    //color = vec4(1.0);

    //color = vec4(fgColor.rgb, fgColor.a * opacity);
    //vec4 bgColor = vec4(0.0, 0.0, 1.0, 1.0);
    //color = mix(bgColor, fgColor, opacity);
	gl_FragDepth = max(0.0, gl_FragCoord.z - (gl_FragCoord.z * depth_offset_index * depthStep));
}
