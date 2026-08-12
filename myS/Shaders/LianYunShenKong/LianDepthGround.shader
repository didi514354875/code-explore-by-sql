// LianDepthGround.shader — 链内深度填充用的纯深度 shader(overrideMaterial)。
// 与角色 LianPrePass 相同的 TransformObjectToHClip 深度(已证明正确)。
// Cull Off + ZTest Always:地面(平面)背面试图在 fork 上写出错误深度,
// 双面 + 无条件写入保证地面深度进入链内深度。
Shader "Hidden/LianYunShenKong/DepthGround"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "DepthGround"
            Cull Off
            ZWrite On
            ZTest Always
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                return half4(0, 0, 0, 1);
            }
            ENDHLSL
        }
    }
}
