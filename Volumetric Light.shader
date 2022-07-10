Shader "Custom/Volumetric Light" {
    Properties {
        [HideInInspector]_NoiseTex ("Noise Texture", 2D) = "white" {}
        [HideInInspector]_ShadowMapTexture ("", any) = "" {}

        [KeywordEnum(Low, Medium, High)] _Quality ("Quality", Int) = 1   // 0 = low, 1 = medium, 2 = high
        _Color ("Fog Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _Density ("Fog Density", Range(0.01, 5.0)) = 0.1
        _SunMult ("Light Intensity", Range(0.01, 20.0)) = 2.0
        _HeightFalloff ("Height Falloff", Range(0.0, 3.0)) = 0.1
        _HeightOffset ("Fog Height Offset", Float) = 0.0

        _ForwardG ("Forward G", Range(0.0, 0.99)) = 0.8
        _BackwardG ("Backward G", Range(0.0, 0.99)) = 0.5
        _GMix ("G Mix", Range(0.0, 1.0)) = 0.5
    }

    SubShader {
        Tags { "Queue"="Transparent+3" "LightMode"="ForwardBase"}
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        GrabPass {
            "_BackgroundTexture"
        }

        Lighting On
        LOD 100
        
        Pass {
            name "Volumetric Light Pass"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            float _Density;
            float _SunMult;
            float _HeightFalloff;
            float _HeightOffset;
            float _ForwardG;
            float _BackwardG;
            float _GMix;
            float4 _Color;

            int _Quality;
            
            sampler2D _CameraDepthTexture;
            sampler2D _NoiseTex;

            float4 _BackgroundTexture_TexelSize;
            float4 _NoiseTex_TexelSize;

            uniform float4 _LightColor0;

            UNITY_DECLARE_SHADOWMAP(_ShadowMapTexture);

            #include "UnityCG.cginc"

            #include "cginc/Syntax.cginc"
            #include "cginc/Utility.cginc"
            #include "cginc/SpaceUtility.cginc"

            #include "cginc/Noise.cginc"
            #include "cginc/VolumetricLight/VolumetricLight.cginc"

            struct v2f {
                float4 texcoord : TEXCOORD0;
                float3 worldDirection : TEXCOORD1;
                float4 vertex : SV_POSITION;
            }; 

            v2f vert (appdata_base v) {
                v2f o;

                o.worldDirection = mul(unity_ObjectToWorld, v.vertex).xyz - _WorldSpaceCameraPos;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.texcoord = ComputeGrabScreenPos(o.vertex);

                return o;
            }

            struct fragOutput {
                float4 color : COLOR;
            };

            fragOutput frag (v2f i) {
                fragOutput o;

                float2 texcoord = i.texcoord.xy / i.texcoord.w;
                float2 fragCoord = texcoord * _BackgroundTexture_TexelSize.zw;

                float3 worldVector = normalize(i.worldDirection);
                float3 forward = normalize(mul((float3x3)unity_CameraToWorld, float3(0,0,1)));
                float linCorrect = 1.0 / dot(worldVector, forward);

                float depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, texcoord));
                float eyeDepth = LinearEyeDepth(depth) * linCorrect;

                eyeDepth = min(eyeDepth, 100.0);
                float3 worldPosition = eyeDepth * worldVector + _WorldSpaceCameraPos;
            
                float dither = bayer16(fragCoord);
                float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);

                float4 volumetricLight = float4(0.0, 0.0, 0.0, 0.0);

                calculateVolumetricLight(volumetricLight, _WorldSpaceCameraPos, worldPosition, worldVector, lightDirection, dither, linCorrect);

                o.color = volumetricLight;

                return o;
            }

            ENDCG
        }
        
        GrabPass {
            "_VolumeLightTexture"
        }

        pass {
            name "Volumetric Light X filter"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #define FILTER_ITTERATION 0   // 0 = x, 1 = y
            #define VL_TEX _VolumeLightTexture
            #define VL_TEX_SIZE _VolumeLightTexture_TexelSize

            #include "cginc/Template/Filter.cginc"

            ENDCG
        }

        GrabPass {
            "_VolumeLightTextureX"
        }

        pass {
            name "Volumetric Light Y filter"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #define FILTER_ITTERATION 1   // 0 = x, 1 = y
            #define VL_TEX _VolumeLightTextureX
            #define VL_TEX_SIZE _VolumeLightTextureX_TexelSize

            #include "cginc/Template/Filter.cginc"

            ENDCG
        }
        
    }
}
