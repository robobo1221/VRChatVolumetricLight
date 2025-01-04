inline half3 worldToShadow( float3 wpos, fixed4 cascadeWeights ) {
    half4 pos = float4(wpos, 1.0);

    half3 sc0 = mul (unity_WorldToShadow[0], pos).xyz;
    half3 sc1 = mul (unity_WorldToShadow[1], pos).xyz;
    half3 sc2 = mul (unity_WorldToShadow[2], pos).xyz;
    half3 sc3 = mul (unity_WorldToShadow[3], pos).xyz;

    half3 shadowMapCoordinate = sc0 * cascadeWeights[0] + sc1 * cascadeWeights[1] + sc2 * cascadeWeights[2] + sc3 * cascadeWeights[3];

    #if defined(UNITY_REVERSED_Z)
        float noCascadeWeights = 1.0 - dot(cascadeWeights, float4(1.0, 1.0, 1.0, 1.0));
        shadowMapCoordinate.z += noCascadeWeights;
    #endif

    return shadowMapCoordinate;
}

inline fixed4 getCascadeWeights(float z) {
    z = max(z, _LightSplitsNear[0]);

    fixed4 zNear = fixed4( z >= _LightSplitsNear );
    fixed4 zFar = fixed4( z < _LightSplitsFar );
    fixed4 weights = zNear * zFar;
    return weights;
}
