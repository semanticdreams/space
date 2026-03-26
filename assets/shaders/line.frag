#version 330 core

#include "clipping.glsl"

smooth in vec4 theColor;
smooth in vec3 worldPos;
out vec4 fragColor;

void main () {
  if (isClipped(worldPos)) {
    discard;
  }
  fragColor = vec4(theColor.rgb * theColor.a, theColor.a);
}
