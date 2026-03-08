uniform mat4 uClipMatrix;

bool isClipPosOutside(vec4 clipPos) {
    return clipPos.x < 0.0 || clipPos.x > 1.0 ||
           clipPos.y < 0.0 || clipPos.y > 1.0;
}

bool isClipped(mat4 clipMatrix, vec3 worldPos) {
    vec4 clipPos = clipMatrix * vec4(worldPos, 1.0);
    return isClipPosOutside(clipPos);
}

bool isClipped(vec3 worldPos) {
    return isClipped(uClipMatrix, worldPos);
}
