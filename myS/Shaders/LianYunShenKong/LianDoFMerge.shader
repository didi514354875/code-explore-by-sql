// LianDoFMerge.shader — pass 24:合并景深结果到 _CameraColorTexture(dump `_25`,线 4241-4247)。
// Blend One SrcAlpha:输出 (DoFResult.rgb, DoFResult.a) — src alpha 混合。
Shader "Hidden/LianYunShenKong/DoFMerge"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "DoFMerge"
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One SrcAlpha

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X(_LianDoFResultTex);
            SAMPLER(sampler_LianDoFResultTex);

            half4 Frag(Varyings input) : SV_Target
            {
                // dump `_25`:直接透传 DoF 结果(rgb × alpha 由 Blend One SrcAlpha 完成)
                return SAMPLE_TEXTURE2D_X(_LianDoFResultTex, sampler_LianDoFResultTex, input.texcoord);
            }
            ENDHLSL
        }
    }
}
