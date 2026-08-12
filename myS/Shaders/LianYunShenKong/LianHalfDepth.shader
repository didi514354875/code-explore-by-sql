// LianHalfDepth.shader — pass 10:半分辨率深度 gather max(仅写深度)。
// dump 线 1972-1984("填写深度buffer"):textureGather 相机深度 → gl_FragDepth = max(四值)。
// 与 pass 8 的深度部分同效果,按 dump 头注释 8/10 两条独立保留。
Shader "Hidden/LianYunShenKong/HalfDepth"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "HalfDepth"
            ZTest Always
            ZWrite On
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 4.5   // Gather 需要 SM5

            // Core.hlsl for XR dependencies
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"

            struct FragmentOutput
            {
                float4 color : SV_Target0;
                float depth : SV_Depth;
            };

            FragmentOutput Frag(Varyings input)
            {
                float4 gathered = _CameraDepthTexture.Gather(sampler_PointClamp, input.texcoord);
                float maxDepth = max(max(gathered.x, gathered.y), max(gathered.z, gathered.w));

                FragmentOutput output;
                output.color = 0.0;
                output.depth = maxDepth;
                return output;
            }
            ENDHLSL
        }
    }
}
