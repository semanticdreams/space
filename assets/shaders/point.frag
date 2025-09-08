#version 330 core
out vec4 FragColor;
in vec4 vertexColor;

void main()
{
    vec2 coord = gl_PointCoord - vec2(0.5);
    if(length(coord) > 0.5)
        discard;
    FragColor = vertexColor;
}