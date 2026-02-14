#version 430 core

layout(location = 0) in vec2 aCorner;
layout(location = 1) in vec4 aLocalCol0;
layout(location = 2) in vec4 aLocalCol1;
layout(location = 3) in vec4 aLocalCol2;
layout(location = 4) in vec4 aLocalCol3;
layout(location = 5) in vec4 aColor;
layout(location = 6) in float aDepthOffsetIndex;
layout(location = 7) in uint aClipGroup;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

smooth out vec4 theColor;
smooth out vec3 worldPos;
smooth out vec3 worldNormal;
flat out float depth_offset_index;
flat out uint clipGroup;

void main()
{
    mat4 local = mat4(aLocalCol0, aLocalCol1, aLocalCol2, aLocalCol3);
    mat4 worldTransform = model * local;
    vec4 world = worldTransform * vec4(aCorner, 0.0, 1.0);
    gl_Position = projection * view * world;
    theColor = aColor;
    worldPos = world.xyz;
    worldNormal = mat3(worldTransform) * vec3(0.0, 0.0, 1.0);
    depth_offset_index = aDepthOffsetIndex;
    clipGroup = aClipGroup;
}
