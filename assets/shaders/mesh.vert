#version 330 core

layout(location=0) in vec2 uv;
layout(location=1) in vec3 normal;
layout(location=2) in vec3 vert;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

out vec2 theUv;
out vec3 worldPos;
out vec3 worldNormal;

void  main() {
    vec4 world = model * vec4(vert, 1.0);
    gl_Position = projection * view * world;
    theUv = uv;
    worldPos = world.xyz;
    worldNormal = mat3(transpose(inverse(model))) * normal;
}
