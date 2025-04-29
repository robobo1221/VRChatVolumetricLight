#include "cginc/Shadow.cginc"
#include "cginc/VolumetricLight/EnergyFunctions.cginc"
#include "cginc/VolumetricLight/VolumetricLightConstants.cginc"

float calculateCloudFBM(float3 position, float3 wind) {
    half fbm = 0.0;

    half frequency = 1.0;
    half amplitude = 0.5;

    [unroll(5)]
    for (uint i = 0; i < 5; i++) {
        float3 newPos = position * frequency + wind;
        fbm += Calculate3DNoise(newPos) * amplitude;

        frequency *= 3.0;
        amplitude *= 0.5;
    }

    return fbm;
}


half calculateDensity(half3 rayPosition) {
    half height = rayPosition.y;

    half3 wind = half3(_Time.y, 0.0, _Time.y) * 0.5;

    half noise = calculateCloudFBM(rayPosition * 0.001 / scale, wind * 0.1);
    noise = noise * noise * (3.0 - 2.0 * noise);

    half bottomGradient = saturate((height - minHeight) / slopeThicknessBottom);
    half topGradient = saturate((maxHeight - height) / slopeThicknessTop);
    half clouds = saturate((noise * 2.0 * bottomGradient * topGradient - 0.5)) * bottomGradient;

    return clouds * _Density / scale;
}

half calculateDepthAlongRay(half3 rayPosition, half3 direction) {
    static uint steps = 8;
    const half rSteps = 1.0 / float(steps);
    
    half rayLength = 10.0 * scale;

    half od = 0.0;

    [unroll(steps)]
    for (uint i = 0; i < steps; i++) {
        float density = calculateDensity(rayPosition) * rayLength;

        od += density;

        rayPosition += direction * rayLength;
        rayLength *= 1.5;
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

    [unroll(8)]
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

void calculateVolumetricLighting(inout half sunScattering, inout half skyScattering, half transmittance, half scatteringIntegral, half extinctionCoeff, half3 rayPosition, half depthAlongRay, half sunPhase, half powder, half currA, half currB) {
    sunScattering += scatteringIntegral * scatteringCoefficient * currA * transmittance * sunPhase * exp(-extinctionCoeff * depthAlongRay * currB) * powder;
    skyScattering += scatteringIntegral * scatteringCoefficient * currA * transmittance;
}

void calculateVolumetricLighting(inout half sunScattering, inout half skyScattering, half3 rayPosition, half3 lightDirection, half opticalDepth, half transmittance, half stepTransmittance, half extinctionCoeff, half density, MultiScatterVariables multiScatter) {
    half scatteringIntegral = (1.0 - stepTransmittance) / extinctionCoeff;

    half depthAlongRay = calculateDepthAlongRay(rayPosition, lightDirection);
    half powderSun = 1.0 - exp(-depthAlongRay * 2.0 * extinctionCoeff);
    half powderView = 1.0 - exp(-opticalDepth * 2.0 * extinctionCoeff);

    half height = (rayPosition.y - minHeight) / thickness;
    half heightTerm = pow(height, height + 1.0) + height + 1.0;

    half powder = powderSun * heightTerm;

    half currA = 1.0;
    half currB = 1.0;

    half accumulatedSkyScattering = 0.0;

    [unroll(multiScatterTerms)]
    for (uint i = 0; i < multiScatterTerms; ++i) {
        half sunPhase = multiScatter.phases[i];
        calculateVolumetricLighting(sunScattering, accumulatedSkyScattering, transmittance, scatteringIntegral, extinctionCoeff, rayPosition, depthAlongRay, sunPhase, powder, currA, currB);
        
        currA *= multiScatterCoeffA;
        currB *= multiScatterCoeffB;
    }

    skyScattering += accumulatedSkyScattering;
}

void calculateVolumetricLight(inout half4 volumetricLight, half3 backgroundColor, half3 startPosition, half3 endPosition, half3 worldVector, half3 lightDirection, half dither, half linCorrect, bool isSky) {
    half3 extinctionCoeff = extinctionCoefficient;

    static uint VL_STEPS = 40;

    const half rSteps = 1.0 / float(VL_STEPS);

    float2 planetSphere = rsi(half3(0.0, earthRadius + _WorldSpaceCameraPos.y, 0.0), worldVector, earthRadius);
    if (planetSphere.y > 0.0 && _WorldSpaceCameraPos.y < minHeight) {
        return;
    }

    float2 topSphere = rsi(half3(0.0, earthRadius + _WorldSpaceCameraPos.y, 0.0), worldVector, earthRadius + maxHeight);
    float2 bottomSphere = rsi(half3(0.0, earthRadius + _WorldSpaceCameraPos.y, 0.0), worldVector, earthRadius + minHeight);

    float startDist = _WorldSpaceCameraPos.y > maxHeight ? topSphere.x : bottomSphere.y;
    float endDist = _WorldSpaceCameraPos.y > maxHeight ? bottomSphere.x : topSphere.y;

    if (_WorldSpaceCameraPos.y > minHeight && _WorldSpaceCameraPos.y < maxHeight) {
        startDist = 0.0;
        float bottomPlane = (minHeight - _WorldSpaceCameraPos.y) / worldVector.y;
        float topPlane = (maxHeight - _WorldSpaceCameraPos.y) / worldVector.y;
        endDist = min(min(max(bottomPlane, topPlane), endDist), 10000.0 * scale);
    }

    if (startDist < 0.0) {
        return;
    }

    if (!isSky) {
        startDist = 0.0;
        endDist = min(length(endPosition - _WorldSpaceCameraPos), endDist);
    }

    startPosition = worldVector * startDist + _WorldSpaceCameraPos;
    endPosition = worldVector * endDist + _WorldSpaceCameraPos;

    half3 increment = (endPosition - startPosition) * rSteps;
    float3 rayPosition = startPosition + increment * dither;
    half stepLength = length(increment);

    half sunScattering = 0.0;
    half skyScattering = 0.0;
    half transmittance = 1.0;
    half opticalDepth = 0.0;

    fixed NoV = dot(lightDirection, worldVector);

    half phaseSky = 0.25 / PI;

    float4 stepPos = half4(0.0, 0.0, 0.0, 0.0);
    
    ShadowRaymarchCascades cascades = generateRaymarchCascadeValues(startPosition, endPosition, rSteps, dither);
    MultiScatterVariables multiScatter = generateMultiScatterValues(NoV);
    //LocalLightVariables localLights = generateLocalLightVariables();

    [loop]
    for (uint i = 0; i < VL_STEPS; ++i) {
        half density = calculateDensity(rayPosition);
        if (density <= 0.0) {
            stepPos += half4(rayPosition, 1.0) * transmittance;
            rayPosition += increment;
            continue;
        }

        opticalDepth += density * stepLength;

        half stepTransmittance = exp(-density * stepLength * extinctionCoeff);

        calculateVolumetricLighting(sunScattering, skyScattering, rayPosition, lightDirection, opticalDepth, transmittance, stepTransmittance, extinctionCoeff, density, multiScatter);
        
        transmittance *= stepTransmittance;
        stepPos += half4(rayPosition, 1.0) * transmittance;

        if (transmittance < 0.01) {
            transmittance = 0.0;
            break;
        }

        rayPosition += increment;
        updateRaymarchCascadePosition(cascades);
    }

    stepPos.xyz = stepPos.xyz / stepPos.w - _WorldSpaceCameraPos; 

    half3 sunLighting = float3(0.0, 0.0, 0.0);
    
    if (_LightColor0.a > 0.0) {
        sunLighting = sunScattering * _LightColor0.rgb * 2.0 * _SunMult;
    }

    half3 skyLighting = skyScattering * phaseSky * unity_IndirectSpecColor.rgb * unity_IndirectSpecColor.a;

    volumetricLight.xyz = (sunLighting + skyLighting) * _Color * PI;
    volumetricLight.a = transmittance;

    if (!isSky) {
        return;
    }
    half3 skyTransmittance = saturate(exp(-length(stepPos.xyz) * half3(1.0, 2.0, 3.0) * 1e-5 / scale) + 0.1);
    volumetricLight.xyz = volumetricLight.xyz * skyTransmittance + backgroundColor * (1.0 - skyTransmittance) * (1.0 - transmittance);
}