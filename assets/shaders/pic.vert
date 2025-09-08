#version 130

in vec3 position;
in vec2 uv;

uniform mat4 projection;
uniform mat4 view;

out vec2 theUv;

void main() {
	gl_Position = projection * view * vec4(position, 1.0);
	theUv = uv;
}