// LianSSSBlur.shader — pass 19:可分离 SSS 横/纵模糊(dump `_64`,线 2997-3077)。
// 采样 _LianSkinDiffuseTex + _LianSkinProfileTex + _LianLinearDepthTex;
// 边缘优化(非皮肤像素沿模糊方向选更"皮肤"侧)、深度拒绝(depthRejectScale·|Δdepth|)、
// 皮肤权重混合,输出 _LianSSSTex。横纵两个 pass 用 _LianSSSDirection 区分(0=横, 1=纵)。
Shader "Hidden/LianYunShenKong/SSSBlur"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "SSSBlurHorizontal"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X(_LianSkinDiffuseTex);
            SAMPLER(sampler_LianSkinDiffuseTex);
            TEXTURE2D_X(_LianSkinProfileTex);
            SAMPLER(sampler_LianSkinProfileTex);
            TEXTURE2D_X(_LianLinearDepthTex);
            SAMPLER(sampler_LianLinearDepthTex);

            float2 _LianSSSTexelSize;   // xy = 1/SSS RT 尺寸
            float _LianSSSDirection;    // 0 = 横向, 1 = 纵向
            float _LianSSSScale;        // SSS 强度(_55._m1)
            int _LianSSSSteps;          // 核步数(_55._m3)
            float4 _LianSSSKernel[8];   // rgb=颜色权重, w=偏移倍数(_55._m2)

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 dirUV = _LianSSSDirection > 0.5
                    ? float2(0.0, _LianSSSTexelSize.y) : float2(_LianSSSTexelSize.x, 0.0);

                float4 center = float4(
                    SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, uv).xyz,
                    1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, uv).x);

                // 边缘优化(dump 线 3004-3045):非皮肤像素沿方向选更"皮肤"侧
                if (center.w > 0.9900000095367431640625)
                {
                    float4 left = float4(
                        SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, uv - dirUV).xyz,
                        1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, uv - dirUV).x);
                    float4 right = float4(
                        SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, uv + dirUV).xyz,
                        1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, uv + dirUV).x);
                    float s1 = clamp(sign(left.w - right.w), 0.0, 1.0);
                    float4 edge = lerp(left, right, s1);
                    float s2 = clamp(sign(center.w - edge.w), 0.0, 1.0);
                    float4 blended = lerp(center, edge, s2);
                    if (blended.w > 0.9900000095367431640625)
                        return blended;
                    center = blended;
                }

                // 深度缩放 + 高斯核(dump 线 3051-3076)
                float texelStep = _LianSSSDirection > 0.5 ? _LianSSSTexelSize.y : _LianSSSTexelSize.x;
                float depthStepSize = texelStep * _LianSSSScale;
                float centerDepth = SAMPLE_TEXTURE2D_X(_LianLinearDepthTex, sampler_LianLinearDepthTex, uv).x;
                float depthScale = depthStepSize * (5.6712818145751953125 / centerDepth);
                float2 offset = _LianSSSDirection > 0.5
                    ? float2(0.0, depthScale) : float2(depthScale, 0.0);

                float4 blurred = float4(center.x * _LianSSSKernel[0].x, center.y * _LianSSSKernel[0].y, center.z * _LianSSSKernel[0].z, 0.0);
                float depthRejectScale = depthStepSize * 1701.384521484375;
                for (int i = 1; i < _LianSSSSteps; ++i)
                {
                    float2 sampleUV = uv + _LianSSSKernel[i].ww * offset;
                    float3 sampleColor = SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, sampleUV).xyz;
                    float sampleDepth = SAMPLE_TEXTURE2D_X(_LianLinearDepthTex, sampler_LianLinearDepthTex, sampleUV).x;
                    float sampleTrans = 1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, sampleUV).x;
                    float depthDiff = clamp(depthRejectScale * abs(sampleDepth - centerDepth), 0.0, 1.0);
                    float3 mixedColor = lerp(sampleColor, center.xyz, depthDiff);
                    float3 adjusted = lerp(mixedColor, center.xyz, sampleTrans);
                    blurred.xyz += _LianSSSKernel[i].xyz * adjusted;
                }

                return float4(blurred.x, blurred.y, blurred.z, center.w);
            }
            ENDHLSL
        }

        // 纵向:同一片段,方向参数由 pass 设置
        Pass
        {
            Name "SSSBlurVertical"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X(_LianSkinDiffuseTex);
            SAMPLER(sampler_LianSkinDiffuseTex);
            TEXTURE2D_X(_LianSkinProfileTex);
            SAMPLER(sampler_LianSkinProfileTex);
            TEXTURE2D_X(_LianLinearDepthTex);
            SAMPLER(sampler_LianLinearDepthTex);

            float2 _LianSSSTexelSize;
            float _LianSSSDirection;
            float _LianSSSScale;
            int _LianSSSSteps;
            float4 _LianSSSKernel[8];

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 dirUV = _LianSSSDirection > 0.5
                    ? float2(0.0, _LianSSSTexelSize.y) : float2(_LianSSSTexelSize.x, 0.0);

                float4 center = float4(
                    SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, uv).xyz,
                    1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, uv).x);

                if (center.w > 0.9900000095367431640625)
                {
                    float4 left = float4(
                        SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, uv - dirUV).xyz,
                        1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, uv - dirUV).x);
                    float4 right = float4(
                        SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, uv + dirUV).xyz,
                        1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, uv + dirUV).x);
                    float s1 = clamp(sign(left.w - right.w), 0.0, 1.0);
                    float4 edge = lerp(left, right, s1);
                    float s2 = clamp(sign(center.w - edge.w), 0.0, 1.0);
                    float4 blended = lerp(center, edge, s2);
                    if (blended.w > 0.9900000095367431640625)
                        return blended;
                    center = blended;
                }

                float texelStep = _LianSSSDirection > 0.5 ? _LianSSSTexelSize.y : _LianSSSTexelSize.x;
                float depthStepSize = texelStep * _LianSSSScale;
                float centerDepth = SAMPLE_TEXTURE2D_X(_LianLinearDepthTex, sampler_LianLinearDepthTex, uv).x;
                float depthScale = depthStepSize * (5.6712818145751953125 / centerDepth);
                float2 offset = _LianSSSDirection > 0.5
                    ? float2(0.0, depthScale) : float2(depthScale, 0.0);

                float4 blurred = float4(center.x * _LianSSSKernel[0].x, center.y * _LianSSSKernel[0].y, center.z * _LianSSSKernel[0].z, 0.0);
                float depthRejectScale = depthStepSize * 1701.384521484375;
                for (int i = 1; i < _LianSSSSteps; ++i)
                {
                    float2 sampleUV = uv + _LianSSSKernel[i].ww * offset;
                    float3 sampleColor = SAMPLE_TEXTURE2D_X(_LianSkinDiffuseTex, sampler_LianSkinDiffuseTex, sampleUV).xyz;
                    float sampleDepth = SAMPLE_TEXTURE2D_X(_LianLinearDepthTex, sampler_LianLinearDepthTex, sampleUV).x;
                    float sampleTrans = 1.0 - SAMPLE_TEXTURE2D_X(_LianSkinProfileTex, sampler_LianSkinProfileTex, sampleUV).x;
                    float depthDiff = clamp(depthRejectScale * abs(sampleDepth - centerDepth), 0.0, 1.0);
                    float3 mixedColor = lerp(sampleColor, center.xyz, depthDiff);
                    float3 adjusted = lerp(mixedColor, center.xyz, sampleTrans);
                    blurred.xyz += _LianSSSKernel[i].xyz * adjusted;
                }

                return float4(blurred.x, blurred.y, blurred.z, center.w);
            }
            ENDHLSL
        }
    }
}
