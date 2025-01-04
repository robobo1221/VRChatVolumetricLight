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

    return min(depth, _MaxRayLength);
}