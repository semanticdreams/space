#version 130

in vec3 position;
in vec2 uv;

uniform mat4 projection;
uniform mat4 view;
uniform vec3 textcolor;

out vec2 theUv;
out vec3 theTextColor;

void main() {
	gl_Position = projection * view * vec4(position, 1.0);
	theUv = uv;
	theTextColor = textcolor;
}