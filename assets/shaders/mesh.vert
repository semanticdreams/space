#version 330 core

layout(location=0) in vec2 uv;
layout(location=1) in vec3 normal;
layout(location=2) in vec3 vert;

uniform mat4 projection;
uniform mat4 view;

out vec2 theUv;

void  main() {
    gl_Position = projection * view * vec4(vert, 1.0);
    theUv = uv;
}