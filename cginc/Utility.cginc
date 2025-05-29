half gaussianDistribution(half x, half strength = 1.0) {
    return exp(-x * x * 0.5 * strength);
}

half gaussianDistributionSquared(half x2, half strength = 1.0) {
    return exp(-x2 * 0.5 * strength);
}

half calculateGaussianWeight(half2 offset, half strength = 1.0) {
    half distSquared = dot(offset, offset);

    return gaussianDistributionSquared(distSquared, strength);
}

half sampleLinearDepth(sampler2D depthTexture, half2 texcoord) {
    half depth = LinearEyeDepth(UNITY_SAMPLE_DEPTH(tex2D(depthTexture, texcoord)));

    return depth;
}

half2 rsi(half3 position, half3 direction, half radius) {
    half PoD = dot(position, direction);
    half radiusSquared = radius * radius;

    half delta = PoD * PoD + radiusSquared - dot(position, position);
    if (delta < 0.0) return half2(-1.0, -1.0);
        delta = sqrt(delta);

    return -PoD + half2(-delta, delta);
}

#define nAbs(x) abs(x + 1e-6)