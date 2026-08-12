// LianCascadeShadow.shader — pass 6:1/4 分辨率级联阴影 → 屏幕空间 _LianCascadeShadowTex(R16F)。
// dump `_96`(线 1194-1405):深度→世界重建 → LianCascadeSample.hlsl(级联选择+dither+5×5 PCF)
// → ×1/25 平方输出 → `_2` 抖动量化(默认关)。
Shader "Hidden/LianYunShenKong/CascadeShadow"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "CascadeShadow"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 5.0   // Gather 需要 SM5

            #pragma shader_feature _MV_QUANTIZE

            // Core.hlsl for XR dependencies
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"
            #include "LianShared.hlsl"
            #include "LianCascadeSample.hlsl"

            int _MV_QUANTIZE_BITS;

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // ---- 世界重建(dump 线 1200-1261)----
                float2 sampleUV = uv + _LianCameraDepthTexelSize.xy * 0.300000011920928955078125;
                float depth = LianSampleSceneDepth(sampleUV);
                float3 worldPos = ComputeWorldSpacePosition(uv, depth, unity_MatrixInvVP);

                float shadow = LianCascadeShadowValue(uv, depth, worldPos, true);
                return float4(shadow, shadow, shadow, 1.0);

                // dump `_2` 抖动量化(默认关,与 pre-pass 同关键字)
                #ifdef _MV_QUANTIZE
                {
                    float dither = LianBayer2x2Value(input.positionCS.xy);
                    uint bits = uint(_MV_QUANTIZE_BITS) & 3u;
                    float d = bits == 1u ? dither * 2.0 : dither;
                    float level = bits == 1u ? 15.0 : 31.0;
                    shadow = round((shadow + d) * level) / level;
                }
                #endif

                return float4(shadow, 0.0, 0.0, 0.0);
            }
            ENDHLSL
        }
    }
}
