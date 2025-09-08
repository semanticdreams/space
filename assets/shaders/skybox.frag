#version 130

in vec3 TexCoords;

uniform samplerCube skybox;

out vec4 color;

void main()
{    
    color = texture(skybox, TexCoords);
}