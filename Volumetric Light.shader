Shader "Custom/Volumetric Light" {
    Properties {
        [HideInInspector]_NoiseTex ("Noise Texture", 2D) = "white" {}
        [HideInInspector]_ShadowMapTexture ("", any) = "" {}
        [HideInInspector]_LightProbeTexture ("Light Probe Texture", 3D) = "" {}
        [HideInInspector]_LightProbeBounds ("Light Probe Bounds", Vector) = (0, 0, 0, 0)
        [HideInInspector]_LightProbeRoot ("Light Probe Root", Vector) = (0, 0, 0, 0)
        [HideInInspector] Instancing ("Instancing", Float) = 1

        [KeywordEnum(Low, Medium, High)] _Quality ("Quality", Int) = 1   // 0 = low, 1 = medium, 2 = high
        _Color ("Fog Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _Density ("Fog Density", Range(0.01, 5.0)) = 0.1
        _SunMult ("Light Intensity", Range(0.01, 20.0)) = 2.0
        _HeightFalloff ("Height Falloff", Range(0.0, 3.0)) = 0.1
        _HeightOffset ("Fog Height Offset", Float) = 0.0
        _LocalLightFadeDist ("Local Light Fade Distance", Float) = 24.0

        _ForwardG ("Forward G", Range(0.0, 0.99)) = 0.8
        _BackwardG ("Backward G", Range(0.0, 0.99)) = 0.5
        _GMix ("G Mix", Range(0.0, 1.0)) = 0.5
        _MaxRayLength ("Max Ray Length", Range(1.0, 500.0)) = 50.0

        [KeywordEnum(Off, On)] _LightProbeActivated ("Enable light probes", Int) = 1
    }

    SubShader {
        Tags { "Queue"="Transparent+3" "LightMode"="Vertex"}
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
            #pragma exclude_renderers d3d11_9x
            #pragma exclude_renderers d3d9
            #pragma multi_compile_local __ _LIGHTPROBEACTIVATED_ON
            #pragma multi_compile_local _QUALITY_LOW _QUALITY_MEDIUM _QUALITY_HIGH

            float _Density;
            float _SunMult;
            float _HeightFalloff;
            float _HeightOffset;
            float _ForwardG;
            float _BackwardG;
            float _GMix;
            float _LocalLightFadeDist;
            float _MaxRayLength;
            float4 _Color;

            int _Quality;
            
            sampler2D _CameraDepthTexture;
            sampler2D _NoiseTex;

            sampler3D _LightProbeTexture;
            float4 _LightProbeRoot;
            float4 _LightProbeBounds;
            int _LightProbeActivated;

            float4 _BackgroundTexture_TexelSize;
            float4 _NoiseTex_TexelSize;

            float _VRChatMirrorMode;
            float3 _VRChatMirrorCameraPos;

            uniform float4 _LightColor0;

            UNITY_DECLARE_SHADOWMAP(_ShadowMapTexture);

            #include "UnityCG.cginc"

            #include "cginc/Syntax.cginc"
            #include "cginc/Utility.cginc"
            #include "cginc/SpaceUtility.cginc"

            #include "cginc/Noise.cginc"
            #include "cginc/VolumetricLight/VolumetricLight.cginc"

            struct v2f {
                half4 vertex : SV_POSITION;
                half4x4 invP : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            half4x4 CreateClipToViewMatrix() {
                half4x4 flipZ = float4x4(1, 0, 0, 0,
                                          0, 1, 0, 0,
                                          0, 0, -1, 1,
                                          0, 0, 0, 1);
                half4x4 scaleZ = float4x4(1, 0, 0, 0,
                                           0, 1, 0, 0,
                                           0, 0, 2, -1,
                                           0, 0, 0, 1);
                half4x4 invP = unity_CameraInvProjection;
                half4x4 flipY = float4x4(1, 0, 0, 0,
                                          0, _ProjectionParams.x, 0, 0,
                                          0, 0, 1, 0,
                                          0, 0, 0, 1);

                half4x4 result = mul(scaleZ, flipZ);
                result = mul(invP, result);
                result = mul(flipY, result);
                result._24 *= _ProjectionParams.x;
                result._42 *= -1;
                return result;
            }

            half4 SVPositionToClipPos(half4 pos) {
                half4 clipPos = float4(((pos.xy / _ScreenParams.xy) * 2 - 1) * int2(1, -1), pos.z, 1);
                #ifdef UNITY_SINGLE_PASS_STEREO
                    clipPos.x -= 2 * unity_StereoEyeIndex;
                #endif
                return clipPos;
            }

            v2f vert (appdata_base v) {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.invP = CreateClipToViewMatrix();

                return o;
            }

            struct fragOutput {
                float4 color : COLOR;
            };

            fragOutput frag (v2f i) {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                fragOutput o;

                half4 clipPos = SVPositionToClipPos(i.vertex);

                half4 uv = ComputeScreenPos(clipPos);

                half2 texcoord = uv.xy / uv.w;
                half2 fragCoord = texcoord * _BackgroundTexture_TexelSize.zw;

                half depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, texcoord));

                half4 viewPos = mul(i.invP, half4(clipPos.xy / clipPos.w, depth, 1));
                viewPos = half4(viewPos.xyz / viewPos.w, 1);
                half3 worldPos = mul(UNITY_MATRIX_I_V, viewPos).xyz - _WorldSpaceCameraPos;

                half3 worldVector = normalize(worldPos);
                half3 viewVector = normalize(viewPos.xyz);

                half linCorrect = 1.0 / -viewVector.z;

                // Calculate the end position of the ray
                half3 endPosition = worldVector * min(length(worldPos), _MaxRayLength) + _WorldSpaceCameraPos;

                half4 nearPlaneView = mul(i.invP, half4(clipPos.xy / clipPos.w, UNITY_REVERSED_Z * 2.0 - 1.0, 1));
                nearPlaneView = half4(nearPlaneView.xyz / nearPlaneView.w, 1);

                // Calculate the start position of the ray
                half3 startPosition = mul(UNITY_MATRIX_I_V, nearPlaneView).xyz;
            
                half dither = bayer16(fragCoord);
                half3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);

                half4 volumetricLight = half4(0.0, 0.0, 0.0, 0.0);

                calculateVolumetricLight(volumetricLight, startPosition, endPosition, worldVector, lightDirection, dither, linCorrect);

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
