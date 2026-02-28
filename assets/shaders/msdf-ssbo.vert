#version 430 core

layout(location = 0) in vec2 quadPos;
layout(location = 1) in vec2 quadUV;
layout(location = 2) in vec2 glyphOffset;
layout(location = 3) in vec2 glyphSize;
layout(location = 4) in vec4 glyphUV;
layout(location = 5) in uint glyphGroup;
layout(location = 6) in vec4 glyphColor;

layout(std430, binding = 0) readonly buffer Groups {
    mat4 groupModel[];
};

uniform mat4 projection;
uniform mat4 view;

out vec2 texCoord;
out vec3 worldPos;
out vec4 textColor;
flat out uint groupIndex;

void main() {
    mat4 M = groupModel[glyphGroup];
    vec2 localPos = quadPos * glyphSize + glyphOffset;
    vec4 world = M * vec4(localPos, 0.0, 1.0);
    gl_Position = projection * view * world;
    worldPos = world.xyz;
    groupIndex = glyphGroup;
    textColor = glyphColor;
    texCoord = mix(glyphUV.xy, glyphUV.zw, quadUV);
}
