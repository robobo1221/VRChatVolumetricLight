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
                float4 texcoord : TEXCOORD0;
                float4 vertex : SV_POSITION;
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
                float2 clipPos = (texcoord.xy * 4.0 - 1.0) * float2(1.0, -1.0);

                if (texcoord.x > 0.5 || texcoord.y > 0.5) discard;

                fragOutput o;

                float3 cameraPos = _VRChatMirrorMode > 0 ? _VRChatMirrorCameraPos : _WorldSpaceCameraPos;
                float3 worldDirection = ClipToWorldPos(float4(clipPos, 1.0, 1.0)) - cameraPos;

                float3 worldVector = normalize(worldDirection);
                float3 forward = normalize(mul((float3x3)unity_CameraToWorld, float3(0,0,1)));
                float linCorrect = 1.0 / dot(worldVector, forward);

                float depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, texcoord * 2.0));

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
