#version 330 core

in vec2 theUv;

uniform sampler2D myTexture;

out vec4 fragColor;

void main () {
    fragColor = texture(myTexture, vec2(theUv.x, 1-theUv.y));
}