#version 130

in vec3 position;
in vec2 uv;
in vec4 textcolor;
in float aDepthOffsetIndex;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

out vec2 texCoord;
out vec4 fgColor;
flat out float depth_offset_index;
smooth out vec3 worldPos;

void main() {
	vec4 world = model * vec4(position, 1.0);
	gl_Position = projection * view * world;
	texCoord = uv;
	fgColor = textcolor;
	depth_offset_index = aDepthOffsetIndex;
	worldPos = world.xyz;
}
