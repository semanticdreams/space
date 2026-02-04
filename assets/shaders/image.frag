#version 130

#include "clipping.glsl"

in vec2 theUv;
in vec4 theTint;
flat in float depth_offset_index;
smooth in vec3 worldPos;
out vec4 outputColor;

uniform sampler2D imageTexture;

const float depthStep = 1e-3;

void main() {
	if (isClipped(worldPos)) {
		discard;
	}
	vec4 sampled = texture(imageTexture, theUv);
	outputColor = sampled * theTint;
	gl_FragDepth = max(0.0, gl_FragCoord.z - (gl_FragCoord.z * depth_offset_index * depthStep));
}
