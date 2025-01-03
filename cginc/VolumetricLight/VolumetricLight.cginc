#include "cginc/Shadow.cginc"
#include "cginc/VolumetricLight/EnergyFunctions.cginc"
#include "cginc/VolumetricLight/VolumetricLightConstants.cginc"

float calculateCloudFBM(float3 position, float3 wind) {
    float fbm = 0.0;

    float frequency = 1.0;
    float amplitude = 0.5;

    for (int i = 0; i < 4; i++) {
        float3 newPos = position * frequency + wind;
        fbm += Calculate3DNoise(newPos) * amplitude;

        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return fbm;
}


float calculateDensity(float3 rayPosition) {
    float height = rayPosition.y;

    //float3 wind = float3(_Time.y, 0.0, _Time.y) * 0.5;

    //float noise = calculateCloudFBM(rayPosition * 0.5, wind);
    //noise = noise * noise * (3.0 - 2.0 * noise);

    return saturate(exp(-(height - _HeightOffset /*- noise * 3.0*/) * _HeightFalloff)) * _Density;
}

float calculateDepthAlongRay(float3 rayPosition, float3 direction) {
    const int steps = 5;
    const float rSteps = 1.0 / float(steps);
    
    float rayLength = 0.1;

    float od = 0.0;

    for (int i = 0; i < steps; i++) {
        float density = calculateDensity(rayPosition) * rayLength;

        od += density;

        rayPosition += direction * rayLength;
        rayLength *= 2.0;
    }

    return od;
}

struct ShadowRaymarchVariables {
    float3 startPosition;
    float3 endPosition;
    float3 increment;
    float3 rayPosition;
};

struct ShadowRaymarchCascades {
    ShadowRaymarchVariables cascade0;
    ShadowRaymarchVariables cascade1;
    ShadowRaymarchVariables cascade2;
    ShadowRaymarchVariables cascade3;
};

struct MultiScatterVariables {
    float phases[multiScatterTerms];
};

struct LocalLightVariables {
    half4 positions[8];
    half4 spotDirections[8];
};

ShadowRaymarchVariables generateRaymarchCascadeVariables(fixed4 cascadeWeight, float3 startPosition, float3 endPosition, float rSteps, float dither) {
    ShadowRaymarchVariables values;

    values.startPosition = worldToShadow(startPosition, cascadeWeight);
    values.endPosition = worldToShadow(endPosition, cascadeWeight);
    values.increment = (values.endPosition - values.startPosition) * rSteps;
    values.rayPosition = values.startPosition + values.increment * dither;

    return values;
}

ShadowRaymarchCascades generateRaymarchCascadeValues(float3 startPosition, float3 endPosition, float rSteps, float dither) {
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

float3 getShadowRayPosition(ShadowRaymarchCascades cascades, float viewZ) {
    fixed4 weights = getCascadeWeights(viewZ);

    return cascades.cascade0.rayPosition * weights.x +
           cascades.cascade1.rayPosition * weights.y +
           cascades.cascade2.rayPosition * weights.z +
           cascades.cascade3.rayPosition * weights.w;
}

MultiScatterVariables generateMultiScatterValues(float NoV) {
    MultiScatterVariables values;
    float phases[multiScatterTerms]; // Local array for computation
    float g1 = _ForwardG;
    float g2 = _BackwardG;

    for (int i = 0; i < multiScatterTerms; ++i) {
        phases[i] = dualLobePhase(NoV, g1, g2);

        g1 = g1 * multiScatterCoeffC;
        g2 = g2 * multiScatterCoeffC;
    }

    values.phases = phases;

    return values;
}

LocalLightVariables generateLocalLightVariables() {
    LocalLightVariables values;

    for (int i = 0; i < 8; i++) {
        values.positions[i] = mul(unity_LightPosition[i], UNITY_MATRIX_V);  // Transpose of view matrix is the inverse.
        values.positions[i].xyz += _WorldSpaceCameraPos;
        values.positions[i].a = unity_LightPosition[i].a;

        values.spotDirections[i] = mul(unity_SpotDirection[i], UNITY_MATRIX_V);
        values.spotDirections[i].a = unity_SpotDirection[i].a;
    }

    return values;
}

float3 calculateCombinedLights(float3 worldPos, float4 lightPos, float3 lightCol, float3 spotDir, float4 qAtten, float3 extinctionCoeff) {
    float3 relPos = worldPos - lightPos.xyz;
    float distSq = dot(relPos, relPos);

    float invDist = rsqrt(distSq);
    float spotEffect = dot(relPos * invDist, -spotDir);
    float atten = saturate(sqrt(qAtten.w) - sqrt(distSq)) / (distSq * qAtten.z + 1e-2);

    float spotAtten = lerp(saturate((spotEffect - qAtten.x) * qAtten.y), 1.0, step(qAtten.x, 0));

    return spotAtten * atten * lightCol * step(1, lightPos.a);
}

float3 calculateLights(float3 worldPos, LocalLightVariables localLights, float3 extinctionCoeff) {
    float3 totalLight = float3(0.0, 0.0, 0.0);
    float max_atten = saturate(_LocalLightFadeDist - length(worldPos - _WorldSpaceCameraPos));

    for (int i = 0; i < 8; i++) {
        float4 lightPos = localLights.positions[i];
        float4 lightAtten = unity_LightAtten[i];
        float3 lightColor = unity_LightColor[i].rgb;

        float3 lightContrib = calculateCombinedLights(
            worldPos, lightPos, lightColor,
            localLights.spotDirections[i].xyz, lightAtten, extinctionCoeff
        );

        totalLight += lightContrib * step(1, lightPos.a);
    }

    totalLight *= max_atten;

    return totalLight;
} 

void calculateVolumetricLighting(inout float3 sunScattering, inout float3 skyScattering, inout float3 localScattering, float3 transmittance, float3 scatteringIntegral, float3 extinctionCoeff, float3 rayPosition, LocalLightVariables localLights, float sunPhase, float shadowMask, float currA) {
    sunScattering += scatteringIntegral * scatteringCoefficient * currA * sunPhase * shadowMask * transmittance;
    
    skyScattering += scatteringIntegral * scatteringCoefficient * currA * transmittance;
    localScattering += scatteringIntegral * scatteringCoefficient * currA * calculateLights(rayPosition, localLights, extinctionCoeff) * transmittance;
}

void calculateVolumetricLighting(inout float3 sunScattering, inout float3 skyScattering, inout float3 localScattering, float3 rayPosition, LocalLightVariables localLights, float3 shadowRayPosition, float3 lightDirection, float3 transmittance, float3 stepTransmittance, float3 extinctionCoeff, float density, MultiScatterVariables multiScatter) {
    float shadowMask = getShadow(shadowRayPosition);

    float3 scatteringIntegral = (1.0 - stepTransmittance) / extinctionCoeff;

    float currA = 1.0;

    float3 accumulatedSkyScattering = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < multiScatterTerms; ++i) {
        float sunPhase = multiScatter.phases[i];
        calculateVolumetricLighting(sunScattering, accumulatedSkyScattering, localScattering, transmittance, scatteringIntegral, extinctionCoeff, rayPosition, localLights, sunPhase, shadowMask, currA);
        
        currA *= multiScatterCoeffA;
    }

    #ifdef _LIGHTPROBEACTIVATED_ON
    float3 probeUv = (rayPosition - _LightProbeRoot) / _LightProbeBounds;
    float padding = 0.2;
    float3 d = abs(probeUv * 2.0 - 1.0);
    float mask = saturate(1.0 - max(max(max(d.x, d.y), d.z) - 1.0, 0.0) / padding);
    mask = mask * mask;

    float3 lightProbeData = tex3D(_LightProbeTexture, probeUv).rgb;

    localScattering += scatteringIntegral * scatteringCoefficient * transmittance * lightProbeData * mask * (1.0 / (1.0 - multiScatterCoeffA));
    accumulatedSkyScattering *= 1.0 - mask;
    #endif

    skyScattering += accumulatedSkyScattering;
}

void calculateVolumetricLight(inout float4 volumetricLight, float3 startPosition, float3 endPosition, float3 worldVector, float3 lightDirection, float dither, float linCorrect) {
    float3 extinctionCoeff = extinctionCoefficient;

    #ifdef _QUALITY_LOW
    const int VL_STEPS = 8;
    #elif _QUALITY_MEDIUM
    const int VL_STEPS = 20;
    #elif _QUALITY_HIGH
    const int VL_STEPS = 40;
    #else 
    const int VL_STEPS = 8;
    #endif

    const float rSteps = 1.0 / float(VL_STEPS);

    float3 increment = (endPosition - startPosition) * rSteps;
    float3 rayPosition = startPosition + increment * dither;
    float stepLength = length(increment);

    float3 sunScattering = float3(0.0, 0.0, 0.0);
    float3 localScattering = float3(0.0, 0.0, 0.0);
    float3 skyScattering = float3(0.0, 0.0, 0.0);
    float3 transmittance = float3(1.0, 1.0, 1.0);
    float opticalDepth = 0.0;

    float NoV = dot(lightDirection, worldVector);

    float phaseSky = 0.25 / PI;
    
    ShadowRaymarchCascades cascades = generateRaymarchCascadeValues(startPosition, endPosition, rSteps, dither);
    MultiScatterVariables multiScatter = generateMultiScatterValues(NoV);
    LocalLightVariables localLights = generateLocalLightVariables();

    for (int i = 0; i < VL_STEPS; ++i) {
        float density = calculateDensity(rayPosition);
        opticalDepth += density * stepLength;

        float3 stepTransmittance = exp(-density * stepLength * extinctionCoeff);

        float viewZ = length(rayPosition - _WorldSpaceCameraPos) * linCorrect;
        float3 shadowRayPosition = getShadowRayPosition(cascades, viewZ);

        calculateVolumetricLighting(sunScattering, skyScattering, localScattering, rayPosition, localLights, shadowRayPosition, lightDirection, transmittance, stepTransmittance, extinctionCoeff, density, multiScatter);
        
        transmittance *= stepTransmittance;

        rayPosition += increment;
        updateRaymarchCascadePosition(cascades);
    }

    float3 sunLighting = float3(0.0, 0.0, 0.0);
    
    if (_LightColor0.a > 0.0) {
        sunLighting = sunScattering * _LightColor0.rgb * 2.0 * _SunMult;
    }

    float3 skyLighting = skyScattering * phaseSky * unity_IndirectSpecColor.rgb;
    float3 localLighting = localScattering * phaseSky * 2.0;

    volumetricLight.xyz = (localLighting + sunLighting + skyLighting) * _Color * PI;
    volumetricLight.a = opticalDepth;
}