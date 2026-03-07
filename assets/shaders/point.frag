#version 330 core

#include "clipping.glsl"
#include "depth-bias.glsl"

out vec4 FragColor;
in vec4 vertexColor;
smooth in vec3 worldPos;
smooth in vec2 localOffset;
flat in float depth_offset_index;

void main()
{
    if (isClipped(worldPos)) {
        discard;
    }
    if(length(localOffset) > 0.5)
        discard;
    FragColor = vertexColor;
    gl_FragDepth = applyDepthOffset(gl_FragCoord.z, depth_offset_index);
}
