#version 330 core

layout(location = 0) in vec3 aVert;
layout(location = 1) in vec4 color;
layout(location = 2) in float aDepthOffsetIndex;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

smooth out vec4 theColor;
smooth out vec3 worldPos;
flat out float depth_offset_index;

void main() {
    vec4 world = model * vec4(aVert, 1.0);
    gl_Position = projection * view * world;
    theColor = color;
    worldPos = world.xyz;
	depth_offset_index = aDepthOffsetIndex;
}
