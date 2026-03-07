const float kDepthOffsetStep = 1e-6;
const float kDepthOffsetMaxBias = 1e-4;

float applyDepthOffset(float depthValue, float depthOffsetIndex) {
    // Depth offsets are only for stable ordering of coplanar layers.
    // Keep bias tiny/capped so real geometry depth ordering always wins.
    float positiveOffset = max(depthOffsetIndex, 0.0);
    float depthBias = min(positiveOffset * kDepthOffsetStep, kDepthOffsetMaxBias);
    return clamp(depthValue - depthBias, 0.0, 1.0);
}
