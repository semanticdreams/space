#version 130

in vec3 position;
in vec2 uv;
in vec4 tint;
in float aDepthOffsetIndex;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

out vec2 theUv;
out vec4 theTint;
flat out float depth_offset_index;
smooth out vec3 worldPos;

void main() {
	vec4 world = model * vec4(position, 1.0);
	gl_Position = projection * view * world;
	theUv = uv;
	theTint = tint;
	depth_offset_index = aDepthOffsetIndex;
	worldPos = world.xyz;
}
