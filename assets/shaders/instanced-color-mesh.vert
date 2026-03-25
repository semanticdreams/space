#version 330 core

layout(location=0) in vec4 aColor;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aVert;
layout(location=3) in vec4 iModel0;
layout(location=4) in vec4 iModel1;
layout(location=5) in vec4 iModel2;
layout(location=6) in vec4 iModel3;

uniform mat4 projection;
uniform mat4 view;

out vec4 theColor;
out vec3 worldPos;
out vec3 worldNormal;

void main() {
    mat4 model = mat4(iModel0, iModel1, iModel2, iModel3);
    vec4 world = model * vec4(aVert, 1.0);
    gl_Position = projection * view * world;
    theColor = aColor;
    worldPos = world.xyz;
    worldNormal = mat3(transpose(inverse(model))) * aNormal;
}
