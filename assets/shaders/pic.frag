#version 130

in vec2 theUv;
out vec4 outputColor;
uniform sampler2D texture;

void main() {
	outputColor = texture2D(texture, theUv);
}