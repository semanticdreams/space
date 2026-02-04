#version 330 core
layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;

uniform mat4 projection;
uniform mat4 view;

smooth out vec3 theColor;
smooth out vec3 worldPos;

void main () {
    gl_Position = projection * view * vec4(position, 1.0);
    theColor = color;
    worldPos = position;
}
