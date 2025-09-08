#version 130

in vec3 position;
in vec2 uv;
in vec4 textcolor;
in int aDepthOffsetIndex;

uniform mat4 projection;
uniform mat4 view;

out vec2 texCoord;
out vec4 fgColor;
flat out int depth_offset_index;

void main() {
	gl_Position = projection * view * vec4(position, 1.0);
	texCoord = uv;
	fgColor = textcolor;
	depth_offset_index = aDepthOffsetIndex;
}