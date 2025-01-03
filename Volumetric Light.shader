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
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float4x4 CreateClipToViewMatrix() {
                float4x4 flipZ = float4x4(1, 0, 0, 0,
                                          0, 1, 0, 0,
                                          0, 0, -1, 1,
                                          0, 0, 0, 1);
                float4x4 scaleZ = float4x4(1, 0, 0, 0,
                                           0, 1, 0, 0,
                                           0, 0, 2, -1,
                                           0, 0, 0, 1);
                float4x4 invP = unity_CameraInvProjection;
                float4x4 flipY = float4x4(1, 0, 0, 0,
                                          0, _ProjectionParams.x, 0, 0,
                                          0, 0, 1, 0,
                                          0, 0, 0, 1);

                float4x4 result = mul(scaleZ, flipZ);
                result = mul(invP, result);
                result = mul(flipY, result);
                result._24 *= _ProjectionParams.x;
                result._42 *= -1;
                return result;
            }

            float4 SVPositionToClipPos(float4 pos) {
                float4 clipPos = float4(((pos.xy / _ScreenParams.xy) * 2 - 1) * int2(1, -1), pos.z, 1);
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

                return o;
            }

            struct fragOutput {
                float4 color : COLOR;
            };

            fragOutput frag (v2f i) {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                fragOutput o;

                float4 clipPos = SVPositionToClipPos(i.vertex);

                float4 uv = ComputeScreenPos(clipPos);

                float2 texcoord = uv.xy / uv.w;
                float2 fragCoord = texcoord * _BackgroundTexture_TexelSize.zw;

                float depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, texcoord));

                float4x4 invP = CreateClipToViewMatrix();
                float4 viewPos = mul(invP, float4(clipPos.xy / clipPos.w, depth, 1));
                viewPos = float4(viewPos.xyz / viewPos.w, 1);

                float3 worldPos = mul(UNITY_MATRIX_I_V, viewPos).xyz;

                float3 cameraPos = (_VRChatMirrorMode > 0) ? _VRChatMirrorCameraPos : _WorldSpaceCameraPos;

                float3 worldVector = normalize(worldPos - cameraPos);
                float3 viewVector = normalize(viewPos.xyz);
                float linCorrect = 1.0 / -viewVector.z;

                float3 worldPosition = worldVector * min(length(viewPos), _MaxRayLength) + cameraPos;
            
                float dither = bayer16(fragCoord);
                float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);

                float4 volumetricLight = float4(0.0, 0.0, 0.0, 0.0);

                calculateVolumetricLight(volumetricLight, cameraPos, worldPosition, worldVector, lightDirection, dither, linCorrect);

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
