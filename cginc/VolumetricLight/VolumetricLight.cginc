#include "cginc/Shadow.cginc"
#include "cginc/VolumetricLight/EnergyFunctions.cginc"
#include "cginc/VolumetricLight/VolumetricLightConstants.cginc"

float calculateCloudFBM(float3 position, float3 wind) {
    half fbm = 0.0;

    half frequency = 1.0;
    half amplitude = 0.5;

    for (uint i = 0; i < 4; i++) {
        float3 newPos = position * frequency + wind;
        fbm += Calculate3DNoise(newPos) * amplitude;

        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return fbm;
}


half calculateDensity(half3 rayPosition) {
    half height = rayPosition.y;

    //float3 wind = float3(_Time.y, 0.0, _Time.y) * 0.5;

    //float noise = calculateCloudFBM(rayPosition * 0.5, wind);
    //noise = noise * noise * (3.0 - 2.0 * noise);

    return saturate(exp(-(height - _HeightOffset /*- noise * 3.0*/) * _HeightFalloff)) * _Density;
}

half calculateDepthAlongRay(half3 rayPosition, half3 direction) {
    const uint steps = 5;
    const half rSteps = 1.0 / float(steps);
    
    half rayLength = 0.1;

    half od = 0.0;

    for (uint i = 0; i < steps; i++) {
        float density = calculateDensity(rayPosition) * rayLength;

        od += density;

        rayPosition += direction * rayLength;
        rayLength *= 2.0;
    }

    return od;
}

struct ShadowRaymarchVariables {
    half3 startPosition;
    half3 endPosition;
    half3 increment;
    half3 rayPosition;
};

struct ShadowRaymarchCascades {
    ShadowRaymarchVariables cascade0;
    ShadowRaymarchVariables cascade1;
    ShadowRaymarchVariables cascade2;
    ShadowRaymarchVariables cascade3;
};

struct MultiScatterVariables {
    half phases[multiScatterTerms];
};

struct LocalLightVariables {
    half4 positions[8];
    half4 spotDirections[8];
};

ShadowRaymarchVariables generateRaymarchCascadeVariables(fixed4 cascadeWeight, half3 startPosition, half3 endPosition, half rSteps, half dither) {
    ShadowRaymarchVariables values;

    values.startPosition = worldToShadow(startPosition, cascadeWeight);
    values.endPosition = worldToShadow(endPosition, cascadeWeight);
    values.increment = (values.endPosition - values.startPosition) * rSteps;
    values.rayPosition = values.startPosition + values.increment * dither;

    return values;
}

ShadowRaymarchCascades generateRaymarchCascadeValues(half3 startPosition, half3 endPosition, half rSteps, half dither) {
    ShadowRaymarchCascades cascadeValues;

    cascadeValues.cascade0 = generateRaymarchCascadeVariables(fixed4(1.0, 0.0, 0.0, 0.0), startPosition, endPosition, rSteps, dither);
    cascadeValues.cascade1 = generateRaymarchCascadeVariables(fixed4(0.0, 1.0, 0.0, 0.0), startPosition, endPosition, rSteps, dither);
    cascadeValues.cascade2 = generateRaymarchCascadeVariables(fixed4(0.0, 0.0, 1.0, 0.0), startPosition, endPosition, rSteps, dither);
    cascadeValues.cascade3 = generateRaymarchCascadeVariables(fixed4(0.0, 0.0, 0.0, 1.0), startPosition, endPosition, rSteps, dither);

    return cascadeValues;
}

void updateRaymarchCascadePosition(inout ShadowRaymarchCascades cascades) {
    cascades.cascade0.rayPosition += cascades.cascade0.increment;
    cascades.cascade1.rayPosition += cascades.cascade1.increment;
    cascades.cascade2.rayPosition += cascades.cascade2.increment;
    cascades.cascade3.rayPosition += cascades.cascade3.increment;
}

half3 getShadowRayPosition(ShadowRaymarchCascades cascades, half viewZ) {
    fixed4 weights = getCascadeWeights(viewZ);

    return cascades.cascade0.rayPosition * weights.x +
           cascades.cascade1.rayPosition * weights.y +
           cascades.cascade2.rayPosition * weights.z +
           cascades.cascade3.rayPosition * weights.w;
}

MultiScatterVariables generateMultiScatterValues(half NoV) {
    MultiScatterVariables values;
    half phases[multiScatterTerms]; // Local array for computation
    half g1 = _ForwardG;
    half g2 = _BackwardG;

    for (uint i = 0; i < multiScatterTerms; ++i) {
        phases[i] = dualLobePhase(NoV, g1, g2);

        g1 = g1 * multiScatterCoeffC;
        g2 = g2 * multiScatterCoeffC;
    }

    values.phases = phases;

    return values;
}

LocalLightVariables generateLocalLightVariables() {
    LocalLightVariables values;

    for (uint i = 0; i < 8; i++) {
        values.positions[i] = mul(unity_LightPosition[i], UNITY_MATRIX_V);  // Transpose of view matrix is the inverse.
        values.positions[i].xyz += _WorldSpaceCameraPos;
        values.positions[i].a = unity_LightPosition[i].a;

        values.spotDirections[i] = mul(unity_SpotDirection[i], UNITY_MATRIX_V);
        values.spotDirections[i].a = unity_SpotDirection[i].a;
    }

    return values;
}

half3 calculateCombinedLights(half3 worldPos, half4 lightPos, half3 lightCol, half3 spotDir, half4 qAtten, half3 extinctionCoeff) {
    half3 relPos = worldPos - lightPos.xyz;
    half distSq = dot(relPos, relPos);

    half invDist = rsqrt(distSq);
    half spotEffect = dot(relPos * invDist, -spotDir);
    half atten = saturate(sqrt(qAtten.w) - sqrt(distSq)) / (distSq * qAtten.z + 1e-2);

    half spotAtten = lerp(saturate((spotEffect - qAtten.x) * qAtten.y), 1.0, step(qAtten.x, 0));

    return spotAtten * atten * lightCol * step(1, lightPos.a);
}

half3 calculateLights(half3 worldPos, LocalLightVariables localLights, half3 extinctionCoeff) {
    half3 totalLight = half3(0.0, 0.0, 0.0);
    half max_atten = saturate(_LocalLightFadeDist - length(worldPos - _WorldSpaceCameraPos));

    for (uint i = 0; i < 8; i++) {
        half4 lightPos = localLights.positions[i];
        half4 lightAtten = unity_LightAtten[i];
        half3 lightColor = unity_LightColor[i].rgb;

        half3 lightContrib = calculateCombinedLights(
            worldPos, lightPos, lightColor,
            localLights.spotDirections[i].xyz, lightAtten, extinctionCoeff
        );

        totalLight += lightContrib * step(1, lightPos.a);
    }

    totalLight *= max_atten;

    return totalLight;
} 

void calculateVolumetricLighting(inout half3 sunScattering, inout half3 skyScattering, inout half3 localScattering, half3 transmittance, half3 scatteringIntegral, half3 extinctionCoeff, half3 rayPosition, LocalLightVariables localLights, half sunPhase, half shadowMask, half currA) {
    sunScattering += scatteringIntegral * scatteringCoefficient * currA * sunPhase * shadowMask * transmittance;
    
    skyScattering += scatteringIntegral * scatteringCoefficient * currA * transmittance;
    localScattering += scatteringIntegral * scatteringCoefficient * currA * calculateLights(rayPosition, localLights, extinctionCoeff) * transmittance;
}

void calculateVolumetricLighting(inout half3 sunScattering, inout half3 skyScattering, inout half3 localScattering, half3 rayPosition, LocalLightVariables localLights, half3 shadowRayPosition, half3 lightDirection, half3 transmittance, half3 stepTransmittance, half3 extinctionCoeff, half density, MultiScatterVariables multiScatter) {
    half shadowMask = getShadow(shadowRayPosition);

    half3 scatteringIntegral = (1.0 - stepTransmittance) / extinctionCoeff;

    half currA = 1.0;

    half3 accumulatedSkyScattering = half3(0.0, 0.0, 0.0);

    for (uint i = 0; i < multiScatterTerms; ++i) {
        half sunPhase = multiScatter.phases[i];
        calculateVolumetricLighting(sunScattering, accumulatedSkyScattering, localScattering, transmittance, scatteringIntegral, extinctionCoeff, rayPosition, localLights, sunPhase, shadowMask, currA);
        
        currA *= multiScatterCoeffA;
    }

    #ifdef _LIGHTPROBEACTIVATED_ON
    half3 probeUv = (rayPosition - _LightProbeRoot) / _LightProbeBounds;
    const half padding = 0.2;
    half3 d = abs(probeUv * 2.0 - 1.0);
    half mask = saturate(1.0 - max(max(max(d.x, d.y), d.z) - 1.0, 0.0) / padding);
    mask = mask * mask;

    half3 lightProbeData = tex3D(_LightProbeTexture, probeUv).rgb;

    localScattering += scatteringIntegral * scatteringCoefficient * transmittance * lightProbeData * mask * (1.0 / (1.0 - multiScatterCoeffA));
    accumulatedSkyScattering *= 1.0 - mask;
    #endif

    skyScattering += accumulatedSkyScattering;
}

void calculateVolumetricLight(inout half4 volumetricLight, half3 startPosition, half3 endPosition, half3 worldVector, half3 lightDirection, half dither) {
    half3 extinctionCoeff = extinctionCoefficient;

    #ifdef _QUALITY_LOW
    const uint VL_STEPS = 8;
    #elif _QUALITY_MEDIUM
    const uint VL_STEPS = 20;
    #elif _QUALITY_HIGH
    const uint VL_STEPS = 40;
    #else 
    const uint VL_STEPS = 8;
    #endif

    const half rSteps = 1.0 / float(VL_STEPS);

    half3 increment = (endPosition - startPosition) * rSteps;
    half3 rayPosition = startPosition + increment * dither;
    half stepLength = length(increment);

    half3 sunScattering = float3(0.0, 0.0, 0.0);
    half3 localScattering = float3(0.0, 0.0, 0.0);
    half3 skyScattering = float3(0.0, 0.0, 0.0);
    half3 transmittance = float3(1.0, 1.0, 1.0);
    half opticalDepth = 0.0;

    fixed NoV = dot(lightDirection, worldVector);

    half phaseSky = 0.25 / PI;
    
    ShadowRaymarchCascades cascades = generateRaymarchCascadeValues(startPosition, endPosition, rSteps, dither);
    MultiScatterVariables multiScatter = generateMultiScatterValues(NoV);
    LocalLightVariables localLights = generateLocalLightVariables();

    for (uint i = 0; i < VL_STEPS; ++i) {
        half density = calculateDensity(rayPosition);
        opticalDepth += density * stepLength;

        half3 stepTransmittance = exp(-density * stepLength * extinctionCoeff);

        half viewZ = length(rayPosition - _WorldSpaceCameraPos);
        half3 shadowRayPosition = getShadowRayPosition(cascades, viewZ);

        calculateVolumetricLighting(sunScattering, skyScattering, localScattering, rayPosition, localLights, shadowRayPosition, lightDirection, transmittance, stepTransmittance, extinctionCoeff, density, multiScatter);
        
        transmittance *= stepTransmittance;

        rayPosition += increment;
        updateRaymarchCascadePosition(cascades);
    }

    half3 sunLighting = float3(0.0, 0.0, 0.0);
    
    if (_LightColor0.a > 0.0) {
        sunLighting = sunScattering * _LightColor0.rgb * 2.0 * _SunMult;
    }

    half3 skyLighting = skyScattering * phaseSky * unity_IndirectSpecColor.rgb;
    half3 localLighting = localScattering * phaseSky * 2.0;

    volumetricLight.xyz = (localLighting + sunLighting + skyLighting) * _Color * PI;
    volumetricLight.a = opticalDepth;
}