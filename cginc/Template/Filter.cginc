sampler2D VL_TEX;

#if FILTER_ITTERATION == 1
sampler2D _BackgroundTexture;
#endif

sampler2D _CameraDepthTexture;

float4 VL_TEX_SIZE;
float _MaxRayLength;
int _Quality;

float _VRChatMirrorMode;

#include "UnityCG.cginc"

#include "cginc/Syntax.cginc"
#include "cginc/Utility.cginc"
#include "cginc/VolumetricLight/VolumetricLightConstants.cginc"

struct v2f {
    half4 texcoord : TEXCOORD0;
    half4 vertex : SV_POSITION;
};

v2f vert (appdata_base v) {
    v2f o;

    o.vertex = UnityObjectToClipPos(v.vertex);
    o.texcoord = ComputeGrabScreenPos(o.vertex);

    return o;
}

struct fragOutput {
    half4 color : COLOR;
};

half4 filterVolumetricLight(sampler2D tex, half2 texcoord) {
    int blurSize = 2;

    half2 rTexelSize = 1.0 / VL_TEX_SIZE.zw;

    half4 result = float4(0.0, 0.0, 0.0, 0.0);
    fixed totalWeight = 0.0;

    half centerDepth = sampleLinearDepth(_CameraDepthTexture, texcoord);

    for (int i = -blurSize; i <= blurSize; i++) {
        half offset = half(i);
        half2 newCoord = texcoord;

        // 0, 1 = x, y
        newCoord[FILTER_ITTERATION] += offset * rTexelSize[FILTER_ITTERATION];

        half offsetDepth = sampleLinearDepth(_CameraDepthTexture, newCoord);
        half depthWeight = exp(-abs(centerDepth - offsetDepth) * 4.0 / centerDepth) + 1e-4;

        half weight = gaussianDistribution(offset * 0.5) * depthWeight;

        result += tex2D(VL_TEX, newCoord) * weight;
        totalWeight += weight;
    }

    return result / totalWeight;
}

fragOutput frag (v2f i) {
    fragOutput o;

    half2 texcoord = i.texcoord.xy / i.texcoord.w;

    // Make sure we don't include the background when passing it throught to the vertical filter.
    #if FILTER_ITTERATION == 0
        o.color = filterVolumetricLight(VL_TEX, texcoord);
    #else
        half4 backgroundColor = tex2D(_BackgroundTexture, texcoord);
        half4 VolumetricLight = filterVolumetricLight(VL_TEX, texcoord);

        half3 transmittance = exp(-VolumetricLight.a * extinctionCoefficient);

        backgroundColor.rgb = backgroundColor.rgb * transmittance + VolumetricLight.rgb;
        
        o.color = backgroundColor;
    #endif

    return o;
}