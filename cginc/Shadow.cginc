fixed getShadow(float3 shadowPosition) {
    return UNITY_SAMPLE_SHADOW(_ShadowMapTexture, shadowPosition);
}