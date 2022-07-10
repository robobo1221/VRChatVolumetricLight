float getShadow(float3 shadowPosition) {
    if (shadowPosition.z < 0.0 || shadowPosition.z > 1.0 || shadowPosition.x < 0.0 || shadowPosition.x > 1.0 || shadowPosition.y < 0.0 || shadowPosition.y > 1.0) {
        return 1.0;
    }

    return UNITY_SAMPLE_SHADOW(_ShadowMapTexture, shadowPosition);
}