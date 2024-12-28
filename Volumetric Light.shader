Shader "Custom/Volumetric Light" {
    Properties {
        [HideInInspector]_NoiseTex ("Noise Texture", 2D) = "white" {}
        [HideInInspector]_ShadowMapTexture ("", any) = "" {}
        [HideInInspector]_LightProbeTexture ("Light Probe Texture", 3D) = "" {}
        [HideInInspector]_LightProbeBounds ("Light Probe Bounds", Vector) = (0, 0, 0, 0)
        [HideInInspector]_LightProbeRoot ("Light Probe Root", Vector) = (0, 0, 0, 0)

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
            #pragma shader_feature _LIGHTPROBEACTIVATED_ON _LIGHTPROBEACTIVATED_OFF
            #pragma shader_feature _QUALITY_LOW _QUALITY_MEDIUM _QUALITY_HIGH

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
                float3 worldDirection : TEXCOORD1;
                float4 vertex : SV_POSITION;
            }; 

            v2f vert (appdata_base v) {
                v2f o;

                float3 cameraPos = _VRChatMirrorMode > 0 ? _VRChatMirrorCameraPos : _WorldSpaceCameraPos;

                o.worldDirection = mul(unity_ObjectToWorld, v.vertex).xyz - cameraPos;
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
                fragOutput o;

                float2 texcoord = i.texcoord.xy / i.texcoord.w;
                float2 fragCoord = texcoord * _BackgroundTexture_TexelSize.zw;

                float3 worldVector = normalize(i.worldDirection);
                float3 forward = normalize(mul((float3x3)unity_CameraToWorld, float3(0,0,1)));
                float linCorrect = 1.0 / dot(worldVector, forward);

                float3 cameraPos = _VRChatMirrorMode > 0 ? _VRChatMirrorCameraPos : _WorldSpaceCameraPos;

                float depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, texcoord));

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
