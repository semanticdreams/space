#version 130

in vec3 TexCoords;

uniform samplerCube skybox;
uniform float brightness;

out vec4 color;

void main()
{    
    vec4 sampleColor = texture(skybox, TexCoords);
    float t = clamp(brightness, -1.0, 1.0);
    if (t < 0.0) {
        color = vec4(mix(sampleColor.rgb, vec3(0.0), -t), sampleColor.a);
    } else {
        color = vec4(mix(sampleColor.rgb, vec3(1.0), t), sampleColor.a);
    }
}
