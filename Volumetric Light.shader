Shader "Custom/Volumetric Light" {
    Properties {
        [HideInInspector]_NoiseTex ("Noise Texture", 2D) = "white" {}
        [HideInInspector]_ShadowMapTexture ("", any) = "" {}
        [HideInInspector]_LightProbeTexture ("Light Probe Texture", 3D) = "" {}
        [HideInInspector]_LightProbeBounds ("Light Probe Bounds", Vector) = (0, 0, 0, 0)
        [HideInInspector]_LightProbeRoot ("Light Probe Root", Vector) = (0, 0, 0, 0)
        _Scale ("Scale", Float) = 2.0

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
            float _Scale;
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
            #include "UnityStandardUtils.cginc"

            #include "cginc/Syntax.cginc"
            #include "cginc/Utility.cginc"
            #include "cginc/SpaceUtility.cginc"

            #include "cginc/Noise.cginc"
            #include "cginc/VolumetricLight/VolumetricLight.cginc"

            struct v2f {
                float4 texcoord : TEXCOORD0;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
            };

            float3 ClipToWorldPos(float4 clipPos) {
            #ifdef UNITY_REVERSED_Z
                // unity_CameraInvProjection always in OpenGL matrix form
                // that doesn't match the current view matrix used to calculate the clip space

                // transform clip space into normalized device coordinates
                float3 ndc = clipPos.xyz / clipPos.w;

                // convert ndc's depth from 1.0 near to 0.0 far to OpenGL style -1.0 near to 1.0 far 
                ndc = float3(ndc.x, ndc.y * _ProjectionParams.x, (1.0 - ndc.z) * 2.0 - 1.0);

                // transform back into clip space and apply inverse projection matrix
                float3 viewPos =  mul(unity_CameraInvProjection, float4(ndc * clipPos.w, clipPos.w));
            #else
                // using OpenGL, unity_CameraInvProjection matches view matrix
                float3 viewPos = mul(unity_CameraInvProjection, clipPos);
            #endif

                // transform from view to world space
                return mul(unity_MatrixInvV, float4(viewPos, 1.0)).xyz;
            }

            v2f vert (appdata_base v) {
                v2f o;
                UNITY_SETUP_INSTANCE_ID( v );
				UNITY_INITIALIZE_OUTPUT( v2f, o );
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO( o );
				UNITY_TRANSFER_INSTANCE_ID( v, o );
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.texcoord = ComputeGrabScreenPos(o.vertex);

                return o;
            }

            struct fragOutput {
                float4 color : COLOR;
            };

            float cameraToMirror(float3 worldVector) {
                float3 planeNormal = worldVector;
                float zNear = _ProjectionParams.y;
                float3 originToCamera = _WorldSpaceCameraPos;

                float originToCameradistance = length(dot(originToCamera, planeNormal));
                float originToPlaneDistance = zNear - originToCameradistance;

                return originToPlaneDistance;
            }

            fragOutput frag (v2f i) {
                if (_VRChatMirrorMode > 0) discard;
                
                float2 texcoord = i.texcoord.xy / i.texcoord.w;
                float2 fragCoord = texcoord * _BackgroundTexture_TexelSize.zw;
                
                texcoord = TransformStereoScreenSpaceTex(texcoord, 1.0);

                if (texcoord.x > 1.1 / _Scale || texcoord.y > 1.1 / _Scale) discard;

                float2 clipPos = (texcoord.xy * _Scale * 2.0 - 1.0) * float2(1.0, -1.0);

                fragOutput o;

                float3 cameraPos = _VRChatMirrorMode > 0 ? _VRChatMirrorCameraPos : _WorldSpaceCameraPos;
                float3 worldDirection = ClipToWorldPos(float4(clipPos, 1.0, 1.0)) - cameraPos;

                float3 worldVector = normalize(worldDirection);
                float3 forward = normalize(mul((float3x3)unity_CameraToWorld, float3(0,0,1)));
                float linCorrect = 1.0 / dot(worldVector, forward);

                float depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, texcoord * _Scale));

                float eyeDepth = LinearEyeDepth(depth) * linCorrect;

                eyeDepth = min(eyeDepth, 50.0);
                float3 worldPosition = eyeDepth * worldVector + cameraPos;
            
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
            name "Downsample Information"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "cginc/Syntax.cginc"
            #include "cginc/Utility.cginc"

            sampler2D _CameraDepthTexture;
            float _Scale;

            struct v2f {
                float4 texcoord : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };
            
            v2f vert (appdata_base v) {
                v2f o;
            
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
                float depth = sampleLinearDepth(_CameraDepthTexture, texcoord * _Scale);

                o.color = float4(depth, 0.0, 0.0, 0.0);

                return o;
            }

            ENDCG
        }

        GrabPass {
            "_VolumeLightTextureDepth"
        }

        pass {
            name "Volumetric Light Upscale filter"
            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "cginc/Syntax.cginc"
            #include "cginc/Utility.cginc"

            sampler2D _CameraDepthTexture;
            sampler2D _VolumeLightTextureDepth;
            sampler2D _VolumeLightTexture;
            float4 _VolumeLightTexture_TexelSize;
            float _Scale;

            // upscale based on downscaled depth and actual depth bilaterally
            float4 upscaleVolumetrics(float2 texcoord) {
                const int blurSize = 2;

                float2 rTexelSize = 1.0 / _VolumeLightTexture_TexelSize.zw;

                float4 center = tex2D(_VolumeLightTexture, texcoord / _Scale);
                float4 result = center;
                float totalWeight = 1.0;

                float centerDepth = sampleLinearDepth(_CameraDepthTexture, texcoord);

                for (int i = -blurSize; i <= blurSize; i++) {
                    for (int j = -blurSize; j <= blurSize; j++) {
                        if (i == 0 && j == 0) {
                            continue;
                        }

                        float2 offset = float2(i, j);
                        float2 newCoord = texcoord + offset * rTexelSize;

                        float offsetDepth = tex2D(_VolumeLightTextureDepth, newCoord / _Scale).r;
                        float depthWeight = exp(-abs(centerDepth - offsetDepth) * 16.0 / centerDepth) + 1e-4;

                        float4 tap = tex2D(_VolumeLightTexture, newCoord / _Scale);

                        float volumetricWeight = depthWeight / (distance(center.rgb, tap.rgb) + 1e-16);

                        result += tex2D(_VolumeLightTexture, newCoord / _Scale) * depthWeight * volumetricWeight;
                        totalWeight += depthWeight * volumetricWeight;
                    }
                }

                return result / totalWeight;
            }

            struct v2f {
                float4 texcoord : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata_base v) {
                v2f o;
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

                o.color = upscaleVolumetrics(texcoord);

                return o;
            }

            ENDCG
        }

        GrabPass {
            "_UpscaledVolumeLightTexture"
        }

        pass {
            name "Volumetric Light X filter"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #define FILTER_ITTERATION 0   // 0 = x, 1 = y
            #define VL_TEX _UpscaledVolumeLightTexture
            #define VL_TEX_SIZE _UpscaledVolumeLightTexture_TexelSize

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
