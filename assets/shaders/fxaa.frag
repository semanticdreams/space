#version 330 core

out vec4 fragColor;
in vec2 v_texCoord;

uniform sampler2D u_colorTexture;

uniform vec2 u_texelStep;
uniform int u_showEdges;
uniform int u_fxaaOn;

uniform float u_lumaThreshold;
uniform float u_mulReduce;
uniform float u_minReduce;
uniform float u_maxSpan;

void main() {
    vec3 rgbM = texture(u_colorTexture, v_texCoord).rgb;

    if (u_fxaaOn == 0) {
        fragColor = vec4(rgbM, 1.0);
        return;
    }

    vec3 rgbNW = textureOffset(u_colorTexture, v_texCoord, ivec2(-1, 1)).rgb;
    vec3 rgbNE = textureOffset(u_colorTexture, v_texCoord, ivec2(1, 1)).rgb;
    vec3 rgbSW = textureOffset(u_colorTexture, v_texCoord, ivec2(-1, -1)).rgb;
    vec3 rgbSE = textureOffset(u_colorTexture, v_texCoord, ivec2(1, -1)).rgb;

    const vec3 toLuma = vec3(0.299, 0.587, 0.114);

    float lumaNW = dot(rgbNW, toLuma);
    float lumaNE = dot(rgbNE, toLuma);
    float lumaSW = dot(rgbSW, toLuma);
    float lumaSE = dot(rgbSE, toLuma);
    float lumaM = dot(rgbM, toLuma);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    if (lumaMax - lumaMin <= lumaMax * u_lumaThreshold) {
        fragColor = vec4(rgbM, 1.0);
        return;
    }

    vec2 samplingDirection;
    samplingDirection.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    samplingDirection.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float samplingDirectionReduce =
        max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.25 * u_mulReduce, u_minReduce);

    float minSamplingDirectionFactor =
        1.0 / (min(abs(samplingDirection.x), abs(samplingDirection.y)) + samplingDirectionReduce);

    samplingDirection =
        clamp(samplingDirection * minSamplingDirectionFactor, vec2(-u_maxSpan), vec2(u_maxSpan)) *
        u_texelStep;

    vec3 rgbSampleNeg = texture(u_colorTexture, v_texCoord + samplingDirection * (1.0 / 3.0 - 0.5)).rgb;
    vec3 rgbSamplePos = texture(u_colorTexture, v_texCoord + samplingDirection * (2.0 / 3.0 - 0.5)).rgb;

    vec3 rgbTwoTab = (rgbSamplePos + rgbSampleNeg) * 0.5;

    vec3 rgbSampleNegOuter = texture(u_colorTexture, v_texCoord + samplingDirection * (0.0 / 3.0 - 0.5)).rgb;
    vec3 rgbSamplePosOuter = texture(u_colorTexture, v_texCoord + samplingDirection * (3.0 / 3.0 - 0.5)).rgb;

    vec3 rgbFourTab = (rgbSamplePosOuter + rgbSampleNegOuter) * 0.25 + rgbTwoTab * 0.5;

    float lumaFourTab = dot(rgbFourTab, toLuma);

    if (lumaFourTab < lumaMin || lumaFourTab > lumaMax) {
        fragColor = vec4(rgbTwoTab, 1.0);
    } else {
        fragColor = vec4(rgbFourTab, 1.0);
    }

    if (u_showEdges != 0) {
        fragColor.r = 1.0;
    }
}
