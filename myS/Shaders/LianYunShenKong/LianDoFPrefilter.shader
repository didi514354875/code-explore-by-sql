// LianDoFPrefilter.shader — pass 21b:2×2 采样 + CoC 权重混合 → 1/2 分辨率(dump `_39`,线 3796-3832)。
// weight = clamp(1 - (maxCoC - coc)·64, 0, 1);blended = Σ rgb·w / Σw;输出 min(rgb, 200)。
Shader "Hidden/LianYunShenKong/DoFPrefilter"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "DoFPrefilter"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            SAMPLER(sampler_BlitTexture);



            float2 _LianDoFPrefilterTexelSize;   // _8._m0.zw: 全分辨率 texel 尺寸
            float2 _LianDoFPrefilterMaxUV;       // _8._m2.xy: uv 上限

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 texel = _LianDoFPrefilterTexelSize;

                // 2×2 采样(dump 线 3798-3810)
                float2 uvA = min(uv + texel * float2(0.5, 0.5), _LianDoFPrefilterMaxUV);
                float2 uvB = min(uv + texel * float2(-0.5, -0.5), _LianDoFPrefilterMaxUV);
                float2 uvC = min(uv + texel * float2(-0.5, 0.5), _LianDoFPrefilterMaxUV);
                float2 uvD = min(uv + texel * float2(0.5, -0.5), _LianDoFPrefilterMaxUV);
                half4 s1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvA);
                half4 s2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvB);
                half4 s3 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvC);
                half4 s4 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvD);

                float maxCoc = max(max(s1.w, s2.w), max(s3.w, s4.w));

                // CoC 权重(dump 线 3811-3830)
                float w1 = clamp(1.0 - (maxCoc - s1.w) * 64.0, 0.0, 1.0);
                float w2 = clamp(1.0 - (maxCoc - s2.w) * 64.0, 0.0, 1.0);
                float w3 = clamp(1.0 - (maxCoc - s3.w) * 64.0, 0.0, 1.0);
                float w4 = clamp(1.0 - (maxCoc - s4.w) * 64.0, 0.0, 1.0);
                float3 blended = s1.xyz * w1 + s2.xyz * w2 + s3.xyz * w3 + s4.xyz * w4;
                blended /= max(w1 + w2 + w3 + w4, 1e-5);

                return half4(min(blended, 200.0), maxCoc);
            }
            ENDHLSL
        }
    }
}
