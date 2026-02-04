#version 330 core

#include "clipping.glsl"

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
    const float depthStep = 1e-3;
    gl_FragDepth = max(0.0, gl_FragCoord.z - (gl_FragCoord.z * depth_offset_index * depthStep));
}
