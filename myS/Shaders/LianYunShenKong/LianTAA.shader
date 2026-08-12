// LianTAA.shader — pass 22:TAA(历史乒乓,dump `_88`,线 3842-4014)。
// 解码运动矢量 → 当前帧 5 tap 十字(YCoCg 工作空间)→ boxMin/boxMax(±_LianTAABoxExpand)→
// 历史采样 + 钳制(CoC 也钳制)→ disocclusion 检测 → 混合 → YCoCg→RGB(PerceptualInvWeight)。
Shader "Hidden/LianYunShenKong/TAA"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "TAA"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            SAMPLER(sampler_BlitTexture);


            #include "LianShared.hlsl"

            TEXTURE2D_X(_LianTAAHistoryPrevTex);
            SAMPLER(sampler_LianTAAHistoryPrevTex);
            TEXTURE2D_X(_LianDoFHalfTex);
            SAMPLER(sampler_LianDoFHalfTex);
            TEXTURE2D_X(_LianMotionVectorTex);
            SAMPLER(sampler_LianMotionVectorTex);

            float4 _LianTAATexelSize;    // _15._m10: xy=texel(1/尺寸), zw=尺寸(像素)
            float4 _LianTAA5TapWeights;  // _20._m0[0..3]: 5 tap 权重(中心用 1-Σ)
            float  _LianTAABoxExpand;    // _20._m2: box 扩展
            float  _LianTAAUseCustomRange; // _20._m3: 自定义范围

            // 工作空间转换(dump 线 3890-3900):rgb/(1+g) 后转 YCoCg
            float3 SceneToWorkingYCoCg(float3 rgb)
            {
                float3 w = rgb / (1.0 + rgb.g);
                // _56.x = dot(_53.xzy, (0.25, 0.25, 0.5)); .y = dot(.xz, (0.5, -0.5)); .z = dot(.xzy, (-0.25,-0.25,0.5))
                return float3(0.25 * w.x + 0.5 * w.z + 0.25 * w.y,
                              0.5 * w.x - 0.5 * w.y,
                              -0.25 * w.x + 0.5 * w.z - 0.25 * w.y);
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                // dump 的 posCS 为 NDC 空间(全屏三角形 w=1 → positionCS.xy)
                float2 posCS = input.positionCS.xy / input.positionCS.w;
                float2 texel = _LianTAATexelSize.xy;
                float2 screenSize = _LianTAATexelSize.zw;

                // ---- 运动矢量(dump 线 3844-3872)----
                float2 mv = LianDecodeMotionVector(SAMPLE_TEXTURE2D_X(_LianMotionVectorTex, sampler_LianMotionVectorTex, uv));
                float2 pixelVector = mv * screenSize * 0.5;   // _75
                float2 oldPosCS = posCS - mv;                 // _158
                float2 absVector = abs(pixelVector) * 2.0;
                float pixelVectorLen = length(pixelVector);
                float addAliasing = min(absVector.x + absVector.y, 1.0);

                // ---- 当前帧 5 tap 十字(dump 线 3873-3900)----
                half4 cUp = SAMPLE_TEXTURE2D_X(_LianDoFHalfTex, sampler_LianDoFHalfTex, uv + texel * float2(0.0, 2.0));
                half4 cDown = SAMPLE_TEXTURE2D_X(_LianDoFHalfTex, sampler_LianDoFHalfTex, uv + texel * float2(0.0, -2.0));
                half4 cLeft = SAMPLE_TEXTURE2D_X(_LianDoFHalfTex, sampler_LianDoFHalfTex, uv + texel * float2(-2.0, 0.0));
                half4 cRight = SAMPLE_TEXTURE2D_X(_LianDoFHalfTex, sampler_LianDoFHalfTex, uv + texel * float2(2.0, 0.0));
                half4 cCenter = SAMPLE_TEXTURE2D_X(_LianDoFHalfTex, sampler_LianDoFHalfTex, uv);

                float3 yccUp = SceneToWorkingYCoCg(cUp.xyz);
                float3 yccDown = SceneToWorkingYCoCg(cDown.xyz);
                float3 yccLeft = SceneToWorkingYCoCg(cLeft.xyz);
                float3 yccRight = SceneToWorkingYCoCg(cRight.xyz);
                float3 yccCenter = SceneToWorkingYCoCg(cCenter.xyz);

                // boxMin/boxMax(dump 线 3902-3922)
                float3 boxMin = min(yccCenter, min(min(yccUp, yccDown), min(yccLeft, yccRight)));
                float3 boxMax = max(yccCenter, max(max(yccUp, yccDown), max(yccLeft, yccRight)));
                float boxMinCoc = min(cCenter.w, min(cUp.w, cDown.w));
                float boxMaxCoc = max(cCenter.w, max(cUp.w, cDown.w));

                // 当前帧加权混合(dump 线 3924-3934)
                float3 filterColor = yccUp * _LianTAA5TapWeights.x + yccDown * _LianTAA5TapWeights.y
                                   + yccLeft * _LianTAA5TapWeights.z + yccRight * _LianTAA5TapWeights.w
                                   + yccCenter * (1.0 - dot(_LianTAA5TapWeights, float4(1, 1, 1, 1)));

                // luma 对比度 → 混合因子(dump 线 3936-3942)
                float lumaContrast = boxMax.x - boxMin.x;
                float blendFactor = clamp(addAliasing * 0.5 + rcp(1.0 + lumaContrast * 128.0), 0.0, 1.0);

                // 屏幕外处理(dump 线 3943-3946)
                bool isOutScreen = max(abs(posCS.x), abs(posCS.y)) >= 1.0;
                filterColor = isOutScreen ? yccCenter : filterColor;
                float3 originCol = lerp(yccCenter, filterColor, blendFactor);

                // ---- 历史采样(dump 线 3947-3970)----
                bool isOldOutScreen = max(abs(oldPosCS.x), abs(oldPosCS.y)) >= 1.0;
                float2 oldPosClamped = clamp(oldPosCS, texel * 2.0 - 1.0, 1.0 - texel * 2.0);
                float2 oldUV = oldPosClamped * 0.5 + 0.5;
                half4 history = SAMPLE_TEXTURE2D_X(_LianTAAHistoryPrevTex, sampler_LianTAAHistoryPrevTex, oldUV);
                float3 hisCol = history.xyz / (1.0 + history.y);
                float hisCoc = clamp(history.w, boxMinCoc, boxMaxCoc);
                bool hisCocLarge = abs(hisCoc) >= 0.100000001490116119384765625;

                // 历史钳制(dump 线 3971-3983)
                float3 hisYCoCg = SceneToWorkingYCoCg(hisCol);
                boxMin -= _LianTAABoxExpand;
                boxMax += _LianTAABoxExpand;
                bool isOutR = any(hisYCoCg < boxMin) || any(boxMax < hisYCoCg);
                float3 hisColFinal = clamp(hisYCoCg, boxMin, boxMax);
                hisColFinal = isOldOutScreen ? originCol : hisColFinal;

                // disocclusion(dump 线 3984-4001)
                float plen = pixelVectorLen / max(pixelVectorLen, 1.0);
                float absL = addAliasing * 0.125 + 0.125;
                float absLOff = addAliasing * absL * 8.0 + 1.0;
                float minYDiff = min(abs(boxMin.y - hisYCoCg.y), abs(boxMax.y - hisYCoCg.y));
                float distC = absL * (absLOff * minYDiff) / (lumaContrast + minYDiff);
                distC = clamp(distC, 0.0, 1.0);
                float distF = max(distC, plen * 0.125);
                distF = min(distF, 0.5);
                float blendF = hisCocLarge ? 0.0 : (1.0 - distF);
                if (_LianTAAUseCustomRange >= 0.5 && isOutR)
                    blendF = 0.0;

                // 混合 + YCoCg→RGB(dump 线 4002-4014)
                float3 finalYCoCg = lerp(originCol, hisColFinal, blendF);
                float y = finalYCoCg.x;
                float co = finalYCoCg.y;
                float cg = finalYCoCg.z;
                float3 rgb = float3(y + co - cg, y + cg, y - co - cg);
                rgb /= max(1.0 - rgb.g, 0.001000000047497451305389404296875);
                return half4(max(rgb, 0.0), cCenter.w);
            }
            ENDHLSL
        }
    }
}
