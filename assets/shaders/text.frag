#version 130

in vec2 theUv;
in vec3 theTextColor;
out vec4 outputColor;
uniform sampler2D myFontTexture;

void main() {
    vec4 background_color = vec4(.0f, .0f, 0.0f, 0.0f);
    float red = texture2D(myFontTexture, theUv).r;
    outputColor = mix(background_color, vec4(theTextColor, 1.0f), red);
}