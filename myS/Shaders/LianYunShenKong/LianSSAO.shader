// LianSSAO.shader — pass 9:1/2 分辨率 SSAO(Scalable Ambient Obscurance 式)。
// dump `_65`(深度重建法线)/ `_69`(法线贴图解码,关键字 _NORMAL_FROM_TEXTURE):
// 视空间重建 → 稳定深度梯度叉积法线 → InterleavedGradientNoise 旋转 12-tap 十字核 →
// AO = Σ saturate(normalCos - angleBias)(× 距离因子, dump 中恒 1)→ 输出
// (1 - ao·强度, 中心线性深度, 0, 0) 到 _LianSSAOTex。
Shader "Hidden/LianYunShenKong/SSAO"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "SSAO"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #pragma shader_feature _NORMAL_FROM_TEXTURE

            // Core.hlsl for XR dependencies
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"
            #include "LianShared.hlsl"

            TEXTURE2D(_LianNormalTex);
            SAMPLER(sampler_LianNormalTex);

            float4 _LianSSAOTexelSize;   // xy = 深度采样偏移(1/全分辨率), zw = 噪声旋转幅度
            float4 _LianSSAOParams;      // _14._m5: x 未用, y = baseRadius, z = angleBias, w = distScale
            float _LianSSAOStrength;     // _14._m6.y

            float SampleLinearDepth(float2 uv)
            {
                return LinearEyeDepth(LianSampleSceneDepth(uv), _ZBufferParams);
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 pixel = input.positionCS.xy;   // gl_FragCoord
                float2 texel = _LianSSAOTexelSize.xy;

                // ---- 视空间重建 + 稳定梯度法线(dump `_65` 线 1578-1660)----
                float depth = LianSampleSceneDepth(uv);
                float linearDepth = LinearEyeDepth(depth, _ZBufferParams);
                float3 pos = ComputeViewSpacePosition(uv, depth, unity_MatrixInvP);

                float3 posL = ComputeViewSpacePosition(uv - float2(texel.x, 0.0), LianSampleSceneDepth(uv - float2(texel.x, 0.0)), unity_MatrixInvP);
                float3 posR = ComputeViewSpacePosition(uv + float2(texel.x, 0.0), LianSampleSceneDepth(uv + float2(texel.x, 0.0)), unity_MatrixInvP);
                float3 posU = ComputeViewSpacePosition(uv - float2(0.0, texel.y), LianSampleSceneDepth(uv - float2(0.0, texel.y)), unity_MatrixInvP);
                float3 posD = ComputeViewSpacePosition(uv + float2(0.0, texel.y), LianSampleSceneDepth(uv + float2(0.0, texel.y)), unity_MatrixInvP);

                // 稳定方向:选梯度更小的那一侧(dump `_51`)
                float3 gx = length(pos - posL) < length(posR - pos) ? (pos - posL) : (posR - pos);
                float3 gy = length(pos - posU) < length(posD - pos) ? (pos - posU) : (posD - pos);
                float3 normal = normalize(cross(gx, gy));
                if (normal.z < 0.0)
                    normal = -normal;   // 朝相机(SAO 约定)

                #if defined(_NORMAL_FROM_TEXTURE)
                {
                    // dump `_69`:解码 _LianNormalTex(世界空间)→ 视空间(dump `_14._m0` = 视图旋转)
                    float3 nWS = LianDecodeNormalSpheremap(_LianNormalTex.Sample(sampler_LianNormalTex, uv).xyz);
                    normal = normalize(mul((float3x3)UNITY_MATRIX_V, nWS));
                }
                #endif

                // ---- 噪声旋转 + 半径(dump `_65` 线 1662-1690)----
                float noise = InterleavedGradientNoise(pixel, 0);
                float angle = noise * 3.1415927410125732421875;
                float2 dir = float2(cos(angle), sin(angle)) * _LianSSAOTexelSize.zw;
                float2 perp = float2(-dir.y, dir.x);
                float jitter = frac((pixel.y - pixel.x) * 0.25);
                float depthScale = min(_LianSSAOParams.y / linearDepth, 12.5);
                float radius = jitter * depthScale + 2.0;
                float d = depthScale;   // dump `_30` 幅度

                // ---- 12 tap(dump 三批:r / r+d / r+2d 环 + 一个 r+3d)----
                float ao = 0.0;
                {
                    float2 offsets[12];
                    offsets[0]  =  dir * radius;
                    offsets[1]  = -dir * radius;
                    offsets[2]  =  perp * radius;
                    offsets[3]  = -perp * radius;
                    offsets[4]  =  dir * (radius + d);
                    offsets[5]  = -dir * (radius + d);
                    offsets[6]  =  perp * (radius + d);
                    offsets[7]  = -perp * (radius + d);
                    offsets[8]  =  dir * (radius + 2.0 * d);
                    offsets[9]  = -dir * (radius + 2.0 * d);
                    offsets[10] =  perp * (radius + 2.0 * d);
                    offsets[11] =  perp * (radius + 3.0 * d);

                    for (int i = 0; i < 12; ++i)
                    {
                        float2 tapUV = uv + offsets[i];
                        float tapDepth = SampleLinearDepth(tapUV);
                        float3 tapPos = ComputeViewSpacePosition(tapUV, LianSampleSceneDepth(tapUV), unity_MatrixInvP);
                        float3 delta = tapPos - pos;
                        float distSq = dot(delta, delta);
                        float normalCos = dot(delta, normal) * rsqrt(max(distSq, 1e-8));
                        float contrib = saturate(normalCos - _LianSSAOParams.z);
                        contrib *= saturate(distSq * _LianSSAOParams.w + 1.0);   // dump `_34`(参数为负时距离衰减)
                        ao += contrib;
                    }
                }

                float occlusion = saturate(1.0 - ao * _LianSSAOStrength);
                return float4(occlusion, linearDepth, 0.0, 0.0);
            }
            ENDHLSL
        }
    }
}
