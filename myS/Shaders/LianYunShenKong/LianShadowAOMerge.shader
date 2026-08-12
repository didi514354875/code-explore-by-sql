// LianShadowAOMerge.shader — pass 11/12/13/15:shadow+AO 合并到 _LianShadowAOTex
// (1/2 分辨率 R8G8B8A8:r=级联阴影, g=soft shadow, b=空, a=AO)。
// 11 非过渡区(stencil Ref 1 Replace,dump `_45` 线 1940-1976)
// 12 过渡区精确 PCF(stencil NotEqual 1,ColorMask RA)
// 13 特殊光 soft shadow g(dump `_57` 线 2230-2400,16 tap 旋转 PCF)
// 15 capsule AO min 合并 a(dump `_66` 线 2528-2600,Blend One One + BlendOp Min)
Shader "Hidden/LianYunShenKong/ShadowAOMerge"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        // 全屏三角形 VS:z 置远平面(反向 Z=0 / 正向 Z=1),配合 ZTest Greater 剔除天空像素
        HLSLINCLUDE
        struct MergeAttributes
        {
            uint vertexID : SV_VertexID;
        };
        struct MergeVaryings
        {
            float4 positionCS : SV_POSITION;
            float2 texcoord : TEXCOORD0;
        };
        MergeVaryings MergeVert(MergeAttributes input)
        {
            MergeVaryings output;
            float2 uv = float2((input.vertexID << 1) & 2, input.vertexID & 2);
            float triZ;
            #if UNITY_REVERSED_Z
            triZ = 0.0;
            #else
            triZ = 1.0;
            #endif
            output.positionCS = float4(uv * 2.0 - 1.0, triZ, 1.0);
            output.texcoord = uv;
            return output;
        }
        ENDHLSL

        // ================================================================
        // pass 11:非过渡区阴影 + AO,写 stencil 1(dump `_45`)
        // ================================================================
        Pass
        {
            Name "ShadowAOMergeNonTransition"
            ZTest Greater
            ZWrite Off
            Cull Off
            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma vertex MergeVert
            #pragma fragment Frag
            #pragma target 5.0   // Gather 需要 SM5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "LianShared.hlsl"

            TEXTURE2D_X(_LianCascadeShadowTex);
            SAMPLER(sampler_LianCascadeShadowTex);
            TEXTURE2D_X(_LianSSAOTex);
            SAMPLER(sampler_LianSSAOTex);

            float4 _LianMergeParams;   // x = 过渡区 shadow 上限(_16._m19,默认 0.9)

            float4 Frag(Varyings input) : SV_Target
            {
                float4 gathered = _LianCascadeShadowTex.Gather(sampler_LianCascadeShadowTex, input.texcoord);
                float sum = gathered.x + gathered.y + gathered.z + gathered.w;
                float shadow = sum * 0.25;
                // 过渡区域(sum > 0.04 且 shadow < 0.9)丢弃,交给 pass 12
                if (sum > 0.039999999105930328369140625 && shadow < _LianMergeParams.x)
                    discard;
                float ao = _LianSSAOTex.Sample(sampler_LianSSAOTex, input.texcoord).x;
                return float4(shadow, 1.0, 1.0, ao);
            }
            ENDHLSL
        }

        // ================================================================
        // pass 12:过渡区精确 PCF 阴影(级联矩阵 + 5×5 PCF,无 dither 换级联)
        // ================================================================
        Pass
        {
            Name "ShadowAOMergeTransition"
            ZTest Greater
            ZWrite Off
            Cull Off
            ColorMask RA
            Stencil {
                Ref 1
                Comp NotEqual
                Pass Keep
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #pragma vertex MergeVert
            #pragma fragment Frag
            #pragma target 5.0   // Gather 需要 SM5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"
            #include "LianShared.hlsl"
            #include "LianCascadeSample.hlsl"

            TEXTURE2D_X(_LianSSAOTex);
            SAMPLER(sampler_LianSSAOTex);

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 sampleUV = uv + _LianCameraDepthTexelSize.xy * 0.300000011920928955078125;
                float depth = LianSampleSceneDepth(sampleUV);
                float3 worldPos = ComputeWorldSpacePosition(uv, depth, unity_MatrixInvVP);
                float shadow = LianCascadeShadowValue(uv, depth, worldPos, false);
                float ao = _LianSSAOTex.Sample(sampler_LianSSAOTex, uv).x;
                return float4(shadow, 0.0, 0.0, ao);
            }
            ENDHLSL
        }

        // ================================================================
        // pass 13:特殊光 soft shadow → g 通道(dump `_57`,16 tap 旋转 PCF,切片 3)
        // ================================================================
        Pass
        {
            Name "ShadowAOMergeSoft"
            ZTest Greater
            ZWrite Off
            Cull Off
            ColorMask G

            HLSLPROGRAM
            #pragma vertex MergeVert
            #pragma fragment Frag
            #pragma target 5.0   // Gather 需要 SM5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"
            #include "LianShared.hlsl"

            TEXTURE2D_ARRAY(_LianShadowAtlasTex);
            SAMPLER(sampler_LianShadowAtlasTex);
            float4 _LianSpecialWorldToShadow[4];
            float2 _LianScreenSize;

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 pixelPos = uv * _LianScreenSize;

                // LianRandFast → 旋转角(dump 线 2230-2252)
                float hash = LianRandFast(pixelPos);
                hash += -0.5;
                float angle = frac(hash) * 6.283185482025146484375;
                float2 randDir = float2(cos(angle), sin(angle));
                // 抖动 = ±2/2048(dump `_207`/`_212`)
                float2 j1 = float2(-randDir.x, randDir.x) * 0.000980000011622905731201171875;
                float2 j2 = float2(-randDir.y, randDir.y) * 0.000980000011622905731201171875;

                // 世界重建(dump 线 2254-2270)
                float depth = LianSampleSceneDepth(uv);
                float3 worldPos = ComputeWorldSpacePosition(uv, depth, unity_MatrixInvVP);

                // 特殊光阴影空间(dump `_20._m0` 行序,含 w 透视除法)
                float4 shadowCS4 = _LianSpecialWorldToShadow[0] * worldPos.x
                                 + _LianSpecialWorldToShadow[1] * worldPos.y
                                 + _LianSpecialWorldToShadow[2] * worldPos.z
                                 + _LianSpecialWorldToShadow[3];
                float3 shadowCoord = shadowCS4.xyz / shadowCS4.w;

                // 16 tap PCF:4 组 gather(dump 线 2272-2330)
                float sum = 0.0;
                {
                    float4 g1 = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(shadowCoord.x + j1.x, shadowCoord.y + j2.x, 3.0));
                    float4 g2 = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(shadowCoord.x + j2.y, shadowCoord.y + j1.y, 3.0));
                    float4 g3 = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(shadowCoord.x + j1.y, shadowCoord.y + j1.x, 3.0));
                    float4 g4 = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(shadowCoord.x + j2.x, shadowCoord.y + j1.y, 3.0));
                    float4 b1 = step(g1, shadowCoord.z);
                    float4 b2 = step(g2, shadowCoord.z);
                    float4 b3 = step(g3, shadowCoord.z);
                    float4 b4 = step(g4, shadowCoord.z);
                    sum = dot(b1, float4(1.0, 1.0, 1.0, 1.0)) + dot(b2, float4(1.0, 1.0, 1.0, 1.0)) + dot(b3, float4(1.0, 1.0, 1.0, 1.0)) + dot(b4, float4(1.0, 1.0, 1.0, 1.0));
                }
                float shadow = sum * 0.0625;   // 1/16
                return float4(1.0, shadow, 1.0, 1.0);
            }
            ENDHLSL
        }

        // ================================================================
        // pass 15:胶囊 AO 4 点深度加权 → a 通道 min 合并(dump `_66`)
        // ================================================================
        Pass
        {
            Name "ShadowAOMergeCapsule"
            ZTest Greater
            ZWrite Off
            Cull Off
            ColorMask A
            Blend One One
            BlendOp Min

            HLSLPROGRAM
            #pragma vertex MergeVert
            #pragma fragment Frag
            #pragma target 5.0   // Gather 需要 SM5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"
            #include "LianShared.hlsl"

            TEXTURE2D_X(_LianCapsuleAOTex);
            SAMPLER(sampler_LianCapsuleAOTex);
            float2 _LianScreenSize;
            float _LianCapsuleAONormDist;

            float DecodeCapsuleDepth(float2 tapUV)
            {
                float2 packed = _LianCapsuleAOTex.Sample(sampler_LianCapsuleAOTex, tapUV).yz * 255.0;
                uint v = (uint(packed.x) << 8u) | uint(packed.y);
                return float(v) * 1.525902189314365386962890625e-05 * _LianCapsuleAONormDist;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float linearDepth = LinearEyeDepth(LianSampleSceneDepth(uv), _ZBufferParams);

                // 1/2 分辨率 RT 坐标(dump 线 2546-2547)
                float halfW = floor(_LianScreenSize.x * 0.5);
                float invHalfW = 1.0 / halfW;
                float2 uv00 = floor(uv * halfW - 0.5) * invHalfW + (invHalfW * 0.5);
                float2 uv10 = uv00 + float2(invHalfW, 0.0);
                float2 uv01 = uv00 + float2(0.0, invHalfW);
                float2 uv11 = uv00 + float2(invHalfW, invHalfW);

                float4 ao4 = float4(
                    _LianCapsuleAOTex.Sample(sampler_LianCapsuleAOTex, uv00).x,
                    _LianCapsuleAOTex.Sample(sampler_LianCapsuleAOTex, uv10).x,
                    _LianCapsuleAOTex.Sample(sampler_LianCapsuleAOTex, uv01).x,
                    _LianCapsuleAOTex.Sample(sampler_LianCapsuleAOTex, uv11).x);
                float4 tapDepth = float4(DecodeCapsuleDepth(uv00), DecodeCapsuleDepth(uv10),
                                         DecodeCapsuleDepth(uv01), DecodeCapsuleDepth(uv11));

                // 深度权重 + 双线性权重(dump 线 2550-2562)
                float4 depthWeights = 1.0 / (abs(tapDepth - linearDepth) + 9.9999997473787516355514526367188e-05);
                float2 f = (uv - uv00) * halfW;
                float4 bilinear = float4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y),
                                         (1.0 - f.x) * f.y, f.x * f.y);
                float4 weights = depthWeights * bilinear;
                float ao = dot(ao4, weights) / max(dot(weights, float4(1.0, 1.0, 1.0, 1.0)), 1e-5);

                return float4(0.0, 0.0, 0.0, ao);
            }
            ENDHLSL
        }
    }
}
