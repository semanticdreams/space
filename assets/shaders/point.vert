#version 330 core
layout(location = 0) in vec2 aOffset;
layout(location = 1) in vec3 aCenter;
layout(location = 2) in vec4 aColor;
layout(location = 3) in float aSize;
layout(location = 4) in float aDepthOffsetIndex;

uniform mat4 projection;
uniform mat4 view;

out vec4 vertexColor;
smooth out vec3 worldPos;
smooth out vec2 localOffset;
flat out float depth_offset_index;

void main()
{
    vec3 right = vec3(view[0][0], view[1][0], view[2][0]);
    vec3 up = vec3(view[0][1], view[1][1], view[2][1]);
    vec3 offset = (right * aOffset.x + up * aOffset.y) * aSize;
    vec3 worldPosition = aCenter + offset;
    gl_Position = projection * view * vec4(worldPosition, 1.0);
    vertexColor = aColor;
    worldPos = worldPosition;
    localOffset = aOffset;
    depth_offset_index = aDepthOffsetIndex;
}
