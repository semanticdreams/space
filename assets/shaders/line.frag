#version 330 core

#include "clipping.glsl"

smooth in vec3 theColor;
smooth in vec3 worldPos;
out vec4 fragColor;

void main () {
  if (isClipped(worldPos)) {
    discard;
  }
  fragColor = vec4(theColor, 1.0);
}
