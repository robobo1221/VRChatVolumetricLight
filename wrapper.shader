Shader "Custom/Volumetric Light wrapper" {
    // Wrapper for volumetric light shader.
    // used to make it easier to use volumetric light shader on open spaces.
    // This forces the shadowmap to be used even when there is no geometry in the scene.

    SubShader {
        Tags {"Queue"="AlphaTest" "LightMode"="ForwardBase" "IgnoreProjector"="True" "RenderType"="TransparentCutout"}
        Cull Off ZWrite Off ZTest Always
        Lighting On
        LOD 100
        Blend Zero SrcColor

        Pass {
            //Blend Zero SrcColor
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #include "UnityCG.cginc"

            struct v2f {
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata_base v) {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);

                return o;
            }

            struct fragOutput {
                float4 color : SV_Target0;
            };

            fragOutput frag (v2f i) {
                fragOutput o;
                o.color = float4(1.0, 1.0, 1.0, 1.0);
                return o;
            }
            ENDCG
        }
    }
}