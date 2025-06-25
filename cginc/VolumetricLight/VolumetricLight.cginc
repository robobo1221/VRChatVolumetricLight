#include "cginc/Shadow.cginc"
#include "cginc/VolumetricLight/EnergyFunctions.cginc"
#include "cginc/VolumetricLight/VolumetricLightConstants.cginc"

float calculateCloudFBM(float3 position, float3 wind) {
    half fbm = 0.0;

    half frequency = 1.0;
    half amplitude = 0.5;

    [unroll(3)]
    for (uint i = 0; i < 3; i++) {
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

    half coverage = Calculate2DNoise(rayPosition.xz * 0.001 / scale + wind.xz * 0.1);

    half erosion = calculateCloudFBM(rayPosition * 0.005 / scale, wind * 0.1);
    erosion = erosion * erosion * (3.0 - 2.0 * erosion);
    
    half bottomGradient = saturate((height - minHeight) / slopeThicknessBottom);
    half topGradient = saturate((maxHeight - height) / slopeThicknessTop);
    half verticalCoverage = 1.0 - bottomGradient * topGradient;
    verticalCoverage = verticalCoverage * verticalCoverage * (3.0 - 2.0 * verticalCoverage);

    half localCoverage = Calculate2DNoise(rayPosition.xz * 2e-4 / scale + wind.xz * 0.01);
    localCoverage = saturate(localCoverage * 4.0 - 1.0);

    half clouds = saturate((coverage * 2.0 * localCoverage - 1.0 - verticalCoverage - erosion * 0.75));

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

    [unroll(multiScatterTerms)]
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

void calculateVolumetricLighting(inout half sunScattering, inout half skyScattering, half transmittance, half scatteringIntegral, half extinctionCoeff, half3 rayPosition, half depthAlongRay, half sunPhase, half powder, half powderAmbient, half currA, half currB) {
    sunScattering += scatteringIntegral * scatteringCoefficient * currA * transmittance * sunPhase * exp(-extinctionCoeff * depthAlongRay * currB) * powder;
    skyScattering += scatteringIntegral * scatteringCoefficient * currA * transmittance * powderAmbient;
}

void calculateVolumetricLighting(inout half sunScattering, inout half skyScattering, half3 rayPosition, half3 lightDirection, half opticalDepth, half transmittance, half stepTransmittance, half extinctionCoeff, half density, MultiScatterVariables multiScatter) {
    half scatteringIntegral = (1.0 - stepTransmittance) / extinctionCoeff;

    half depthAlongRay = calculateDepthAlongRay(rayPosition, lightDirection);
    half powderSun = 1.0 - exp(-depthAlongRay * 2.0 * extinctionCoeff);
    half powderView = 1.0 - exp(-opticalDepth * extinctionCoeff);

    half height = (rayPosition.y - minHeight) / thickness;
    half heightTerm = pow(powderSun, height + 1.0) + height + 1.0;

    half powder = powderSun * heightTerm;
    //half powderAmbient = powderView * (pow(powderView, 1.0 / height + 1.0) + height + 1.0);

    half currA = 1.0;
    half currB = 1.0;

    half accumulatedSkyScattering = 0.0;

    [unroll(multiScatterTerms)]
    for (uint i = 0; i < multiScatterTerms; ++i) {
        half sunPhase = multiScatter.phases[i];
        calculateVolumetricLighting(sunScattering, accumulatedSkyScattering, transmittance, scatteringIntegral, extinctionCoeff, rayPosition, depthAlongRay, sunPhase, powder, 1.0, currA, currB);
        
        currA *= multiScatterCoeffA;
        currB *= multiScatterCoeffB;
    }

    skyScattering += accumulatedSkyScattering;
}

half3 calculateFogOpticalDepth(half3 coeff, half3 position, half3 cameraPos, half depth, half heightOffset, half heightFalloff) {
    half height = position.y;

    half yc   = cameraPos.y - heightOffset;
    half yf   = height - heightOffset;

    half expC = exp(-yc * heightFalloff);
    half expF = exp(-yf * heightFalloff);

    half heighComp = abs(yc - yf);

    // Make sure we don't divide by zero
    if (heighComp < 1e-6) {
        return coeff * depth * expF / scale;
    }

    half solvedHeight = abs(expF - expC) / (heightFalloff * heighComp);

    // optical depth (analytic)
    return coeff * depth * solvedHeight / scale;
}

float3 calculateHeightFog(float3 backgroundColor, half3 position, half depth, half mask) {
    half3 rayLeighOpticalDepth = calculateFogOpticalDepth(fogCoeffRayleigh, position, _WorldSpaceCameraPos, depth, 0.0, fogHeightFalloffRayleigh);
    half3 mieOpticalDepth = calculateFogOpticalDepth(fogCoeffMie, position, _WorldSpaceCameraPos, depth, 0.0, fogHeightFalloffMie);

    half3 opticalDepth = rayLeighOpticalDepth + mieOpticalDepth;
    half3 transmittance = exp(-opticalDepth);
    half3 scattering = 1.0 - transmittance;

    half3 ambientTerm = unity_IndirectSpecColor.rgb * unity_IndirectSpecColor.a * rPI * 0.5;
    half3 directTerm = _LightColor0.rgb * _SunMult * rPI * 2.0;

    half3 fogColor = ambientTerm + directTerm;

    return backgroundColor.rgb * transmittance + fogColor * scattering * mask;
}

void calculateVolumetricLight(inout half4 volumetricLight, half3 backgroundColor, half3 startPosition, half3 endPosition, half3 worldVector, half3 lightDirection, half dither, half linCorrect, bool isSky) {
    half3 extinctionCoeff = extinctionCoefficient;

    static uint VL_STEPS = 48;

    const half rSteps = 1.0 / float(VL_STEPS);

    float2 planetSphere = rsi(half3(0.0, earthRadius + 1.0, 0.0), worldVector, earthRadius);
    if (planetSphere.y > 0.0 && _WorldSpaceCameraPos.y < minHeight || worldVector.y > 0.0 && _WorldSpaceCameraPos.y > maxHeight) {
        return;
    }

    half adjustedMaxHeight = maxHeight;

    float2 topSphere = rsi(half3(0.0, earthRadius + _WorldSpaceCameraPos.y, 0.0), worldVector, earthRadius + adjustedMaxHeight);
    float2 bottomSphere = rsi(half3(0.0, earthRadius + _WorldSpaceCameraPos.y, 0.0), worldVector, earthRadius + minHeight);

    float startDist = _WorldSpaceCameraPos.y > adjustedMaxHeight ? topSphere.x : bottomSphere.y;
    float startDistTemp = startDist;
    float endDist = _WorldSpaceCameraPos.y > adjustedMaxHeight ? bottomSphere.x : topSphere.y;

    if (_WorldSpaceCameraPos.y > minHeight && _WorldSpaceCameraPos.y < adjustedMaxHeight) {
        startDist = length(startPosition - _WorldSpaceCameraPos);
        float bottomPlane = (minHeight - _WorldSpaceCameraPos.y) / worldVector.y;
        float topPlane = (adjustedMaxHeight - _WorldSpaceCameraPos.y) / worldVector.y;
        endDist = min(min(max(bottomPlane, topPlane), endDist), 10000.0 * scale);
    }

    if (startDist < 0.0) {
        return;
    }

    if (!isSky) {
        startDist = endDist > startDistTemp && startDistTemp > 0 ? startDistTemp : length(startPosition - _WorldSpaceCameraPos);
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
    
    //ShadowRaymarchCascades cascades = generateRaymarchCascadeValues(startPosition, endPosition, rSteps, dither);
    MultiScatterVariables multiScatter = generateMultiScatterValues(NoV);
    //LocalLightVariables localLights = generateLocalLightVariables();

    [loop]
    for (uint i = 0; i < VL_STEPS; ++i) {
        rayPosition += increment;
        float3 rayPos = rayPosition;
        rayPos.y = length(rayPos + float3(-_WorldSpaceCameraPos.x, earthRadius, -_WorldSpaceCameraPos.z)) - earthRadius;

        half density = calculateDensity(rayPos);
        if (density <= 0.0) {
            continue;
        }

        opticalDepth += density * stepLength;

        half stepTransmittance = exp(-density * stepLength * extinctionCoeff);

        calculateVolumetricLighting(sunScattering, skyScattering, rayPos, lightDirection, opticalDepth, transmittance, stepTransmittance, extinctionCoeff, density, multiScatter);
        
        stepPos += half4(rayPos, 1.0) * transmittance;
        transmittance *= stepTransmittance;

        if (transmittance < 0.01) {
            transmittance = 0.0;
            break;
        }
        //updateRaymarchCascadePosition(cascades);
    }

    stepPos.xyz = stepPos.xyz / max(stepPos.w, 1.0e-6) - _WorldSpaceCameraPos; 

    half3 sunLighting = float3(0.0, 0.0, 0.0);
    
    if (_LightColor0.a > 0.0) {
        sunLighting = sunScattering * _LightColor0.rgb * 2.0 * _SunMult;
    }

    half3 skyLighting = skyScattering * phaseSky * unity_IndirectSpecColor.rgb * unity_IndirectSpecColor.a;

    volumetricLight.xyz = (sunLighting + skyLighting) * _Color * PI;
    volumetricLight.a = transmittance;
    
    volumetricLight.xyz = calculateHeightFog(volumetricLight.xyz, stepPos.xyz + _WorldSpaceCameraPos, length(stepPos), (1.0 - transmittance));
}