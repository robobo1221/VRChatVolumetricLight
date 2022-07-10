float calculateGaussianWeight(float2 offset, float strength = 1.0) {
    float distSquared = dot(offset, offset);

    return exp(-distSquared * 0.5 * strength);
}

float sampleLinearDepth(sampler2D depthTexture, float2 texcoord) {
    float depth = LinearEyeDepth(UNITY_SAMPLE_DEPTH(tex2D(depthTexture, texcoord)));

    return min(depth, 50.0);
}