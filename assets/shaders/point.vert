#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec4 aColor;
layout(location = 2) in float aPointSize;

uniform mat4 projection;
uniform mat4 view;

out vec4 vertexColor;
void main()
{
    gl_Position = projection * view * vec4(aPos, 1.0);
    gl_PointSize = aPointSize;
    vertexColor = aColor;
}