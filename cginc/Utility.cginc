float gaussianDistribution(float x, float strength = 1.0) {
    return exp(-x * x * 0.5 * strength);
}

float gaussianDistributionSquared(float x2, float strength = 1.0) {
    return exp(-x2 * 0.5 * strength);
}

float calculateGaussianWeight(float2 offset, float strength = 1.0) {
    float distSquared = dot(offset, offset);

    return gaussianDistributionSquared(distSquared, strength);
}

float sampleLinearDepth(sampler2D depthTexture, float2 texcoord) {
    float depth = LinearEyeDepth(UNITY_SAMPLE_DEPTH(tex2D(depthTexture, texcoord)));

    return min(depth, _MaxRayLength);
}