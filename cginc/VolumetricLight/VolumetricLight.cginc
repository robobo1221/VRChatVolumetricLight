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

    float3 wind = float3(_Time.y, 0.0, _Time.y) * 0.5;

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

MultiScatterVariables generadeMultiScatterValues(float NoV) {
    MultiScatterVariables values;
    float g1 = _ForwardG;
    float g2 = _BackwardG;
    
    for (int i = 0; i < multiScatterTerms; ++i) {
        values.phases[i] = dualLobePhase(NoV, g1, g2);

        g1 = g1 * multiScatterCoeffC;
        g2 = g2 * multiScatterCoeffC;
    }

    return values;
}

float3 caclulatePointLight(float3 worldPos, float3 worldVector, float3 lightPos, float3 lightCol, float4 qAtten, float3 extinctionCoeff, float currb) {
    float3 relPos = worldPos - lightPos;
    float distSq = dot(relPos, relPos);

    if (qAtten.w < distSq) return float3(0.0, 0.0, 0.0);

    float atten = 1.0 / (distSq * qAtten.z + 1.0);
    //half3 lightdir = normalize(lightPos - worldPos);

    //float NoV = dot(lightdir, worldVector);

    //float phase = dualLobePhase(NoV, _ForwardG, _BackwardG);

    return lightCol /* * phase */ * atten * exp(-sqrt(distSq) * extinctionCoeff * _Density * currb);
}

float3 calculateSpotLight(float3 worldPos, float3 worldVector, float3 lightPos, float3 lightCol, float3 spotDir, float4 qAtten, float3 extinctionCoeff, float currb) {
    half3 worldToLight = normalize(worldPos - lightPos);
    half spotEffect = dot(worldToLight, -spotDir);

    if (spotEffect < qAtten.x) return float3(0.0, 0.0, 0.0);
    
    float3 relPos = worldPos - lightPos;
    float distSq = dot(relPos, relPos);

    if (qAtten.w < distSq * spotEffect * spotEffect) return float3(0.0, 0.0, 0.0);

    float atten = 1.0 / (distSq * qAtten.z + 1.0);
    
    half spotAtten = saturate((spotEffect - qAtten.x) * qAtten.y);
    //float NoV = dot(-worldToLight, worldVector);

    //float phase = dualLobePhase(NoV, _ForwardG, _BackwardG);

    return spotAtten * lightCol /* * phase */ * exp(-sqrt(distSq) * extinctionCoeff * _Density * currb);
}

float3 calculateLights(float3 worldPos, float3 viewVector, float3 extinctionCoeff, float currb) {
    float3 totalLight = float3(0.0, 0.0, 0.0);
    float3 viewPos = mul(UNITY_MATRIX_V, float4(worldPos, 1.0)).xyz;

    for (int i = 0; i < 8; i++) {
        if (unity_LightPosition[i].a != 1) {
            continue;
        }

        if (unity_LightAtten[i].x != -1) {
            totalLight += calculateSpotLight(viewPos, viewVector, unity_LightPosition[i].xyz, unity_LightColor[i].rgb, unity_SpotDirection[i].xyz, unity_LightAtten[i], extinctionCoeff, currb);
        } else {
            totalLight += caclulatePointLight(viewPos, viewVector, unity_LightPosition[i].xyz, unity_LightColor[i].rgb, unity_LightAtten[i], extinctionCoeff, currb);
        }
    }

    return totalLight;
}

void calculateVolumetricLighting(inout float3 sunScattering, inout float3 skyScattering, inout float3 localScattering, float3 transmittance, float3 scatteringIntegral, float3 extinctionCoeff, float3 rayPosition, float3 viewVector, float sunPhase, float shadowMask, float depthToSun, float depthToSky, float currA, float currB) {
    float3 sunShadowing = exp(-depthToSun * extinctionCoeff * currB);
    float3 skyShadowing = exp(-depthToSky * extinctionCoeff * currB);
    
    sunScattering += scatteringIntegral * scatteringCoefficient * currA * sunPhase * sunShadowing * shadowMask * transmittance;
    skyScattering += scatteringIntegral * scatteringCoefficient * currA * skyShadowing * transmittance;
    localScattering += scatteringIntegral * scatteringCoefficient * currA * calculateLights(rayPosition, viewVector, extinctionCoeff, currB) * transmittance;
}

void calculateVolumetricLighting(inout float3 sunScattering, inout float3 skyScattering, inout float3 localScattering, float3 rayPosition, float3 viewVector, float3 shadowRayPosition, float3 lightDirection, float3 transmittance, float3 stepTransmittance, float3 extinctionCoeff, float density, MultiScatterVariables multiScatter) {
    float shadowMask = getShadow(shadowRayPosition);
    float depthToSun = calculateDepthAlongRay(rayPosition, lightDirection);
    float depthToSky = density;

    float3 scatteringIntegral = (1.0 - stepTransmittance) / extinctionCoeff;

    float currA = 1.0;
    float currB = 1.0;

    for (int i = 0; i < multiScatterTerms; ++i) {
        float sunPhase = multiScatter.phases[i];
        calculateVolumetricLighting(sunScattering, skyScattering, localScattering, transmittance, scatteringIntegral, extinctionCoeff, rayPosition, viewVector, sunPhase, shadowMask, depthToSun, depthToSky, currA, currB);
        
        currA *= multiScatterCoeffA;
        currB *= multiScatterCoeffB;
    }
}

int getVlSteps() {
    int VL_STEPS = 20;

    switch(_Quality) {
    case 0:
        VL_STEPS = 8;
        break;
    case 1:
        VL_STEPS = 20;
        break;
    case 2:
        VL_STEPS = 40;
        break;
    }

    return VL_STEPS;
}

void calculateVolumetricLight(inout float4 volumetricLight, float3 startPosition, float3 endPosition, float3 worldVector, float3 lightDirection, float dither, float linCorrect) {
    float3 extinctionCoeff = extinctionCoefficient;

    int VL_STEPS = getVlSteps();

    float rSteps = 1.0 / float(VL_STEPS);
    
    float3 viewPos = mul(UNITY_MATRIX_V, float4(endPosition, 1.0)).xyz;
    float3 viewVector = normalize(viewPos);

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
    MultiScatterVariables multiScatter = generadeMultiScatterValues(NoV);

    for (int i = 0; i < VL_STEPS; ++i) {
        float density = calculateDensity(rayPosition);
        opticalDepth += density * stepLength;

        float3 stepTransmittance = exp(-density * stepLength * extinctionCoeff);

        float viewZ = length(rayPosition - _WorldSpaceCameraPos) * linCorrect;
        float3 shadowRayPosition = getShadowRayPosition(cascades, viewZ);

        calculateVolumetricLighting(sunScattering, skyScattering, localScattering, rayPosition, viewVector, shadowRayPosition, lightDirection, transmittance, stepTransmittance, extinctionCoeff, density, multiScatter);
        
        transmittance *= stepTransmittance;

        rayPosition += increment;
        updateRaymarchCascadePosition(cascades);
    }

    float3 sunLighting = sunScattering * _LightColor0.rgb * 2.0 * _SunMult;
    float3 skyLighting = skyScattering * phaseSky * unity_IndirectSpecColor.rgb;
    float3 localLighting = localScattering * phaseSky;

    volumetricLight.xyz = (sunLighting + skyLighting + localLighting) * _Color * PI;
    volumetricLight.a = opticalDepth;
}