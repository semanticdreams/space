#version 330 core
smooth in vec3 theColor;
out vec4 fragColor;

void main () {
  fragColor = vec4(theColor, 1.0);
}