#version 130

in vec3 TexCoords;

uniform samplerCube skybox;
uniform float brightness;

out vec4 color;

void main()
{    
    vec4 sampleColor = texture(skybox, TexCoords);
    float t = clamp(brightness, -1.0, 1.0);
    vec3 base;
    if (t < 0.0) {
        base = mix(sampleColor.rgb, vec3(0.0), -t);
    } else {
        base = mix(sampleColor.rgb, vec3(1.0), t);
    }
    color = vec4(base, sampleColor.a);
}
