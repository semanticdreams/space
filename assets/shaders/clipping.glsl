uniform mat4 uClipMatrix;

bool isClipped(vec3 worldPos) {
    vec4 c = uClipMatrix * vec4(worldPos, 1.0);
    return c.x < -1.0 || c.x > 1.0 ||
           c.y < -1.0 || c.y > 1.0;
}
