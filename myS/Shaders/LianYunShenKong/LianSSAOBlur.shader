// LianSSAOBlur.shader — pass 9 后半:十字核模糊。
// dump `_33`(线 1959-1977):9 tap 权重 0.16/0.04/0.08(对角 2×0.16 + 中心 0.04 + 十字 4×0.08),
// 输出 x 通道,其余 0。
Shader "Hidden/LianYunShenKong/SSAOBlur"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "SSAOBlur"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            // Core.hlsl for XR dependencies
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // _BlitTexture 由 Blit.hlsl 声明;仅补 sampler
            SAMPLER(sampler_BlitTexture);

            float4 _LianSSAOBlurTexelSize;   // xy = 1/SSAO RT 尺寸

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 texel = _LianSSAOBlurTexelSize.xy;

                // dump `_33`:对角 (±1.5, ∓1.5) × 0.16, 十字 (±1.5, 0)/(0, ±1.5) × 0.08, 中心 × 0.04
                float4 col = 0.0;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2(1.5, -1.5) * texel).x * 0.16;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2(1.5, 1.5) * texel).x * 0.16;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv).x * 0.04;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2(-1.5, 0.0) * texel).x * 0.08;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2(1.5, 0.0) * texel).x * 0.08;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2(0.0, -1.5) * texel).x * 0.08;
                col.x += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2(0.0, 1.5) * texel).x * 0.08;
                return col;
            }
            ENDHLSL
        }
    }
}
