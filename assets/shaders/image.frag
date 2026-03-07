#version 130

#include "clipping.glsl"
#include "depth-bias.glsl"

in vec2 theUv;
in vec4 theTint;
flat in float depth_offset_index;
smooth in vec3 worldPos;
out vec4 outputColor;

uniform sampler2D imageTexture;

void main() {
	if (isClipped(worldPos)) {
		discard;
	}
	vec4 sampled = texture(imageTexture, theUv);
	outputColor = sampled * theTint;
	gl_FragDepth = applyDepthOffset(gl_FragCoord.z, depth_offset_index);
}
