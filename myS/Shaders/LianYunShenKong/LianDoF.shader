// LianDoF.shader — pass 23:DOF gather。
// pass 0 = dump `_46`(线 4023-4061,环形 4×2 采样,weight=1/(|cocDiff|+0.05));
// pass 1 = dump `_85`(线 4071-4236,CoD AW 式远近 gather:FarCocAreaFactor、shiftCocFactor、
// 双层环采样、focus_weight、归一化 lerp)。默认用 pass 1。
Shader "Hidden/LianYunShenKong/DoF"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        // pass 0:环形 8 tap(dump `_46`)
        Pass
        {
            Name "DoFGatherRing"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragRing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            SAMPLER(sampler_BlitTexture);



            float4 _LianDoFParams;   // x=minBlurRadius, y=radiusMult, z=cocOffset, w=aspect

            half4 FragRing(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float sampleRadius = _LianDoFParams.y * 0.20000000298023223876953125;
                float aspect = _LianDoFParams.w * _LianDoFParams.x;

                half4 centerColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);
                float3 totalCol = centerColor.xyz * 20.0;
                float totalWeight = 20.0;
                for (uint i = 0u; i < 4u; ++i)
                {
                    float angle = float(i) * 0.785398185253143310546875;   // π/4
                    float2 dir = float2(cos(angle), sin(angle));
                    float2 offset = sampleRadius * dir;
                    offset.y *= aspect;
                    half4 s1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + offset);
                    half4 s2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv - offset);
                    float w1 = 1.0 / (abs(centerColor.w - s1.w) + 0.0500000007450580596923828125);
                    float w2 = 1.0 / (abs(centerColor.w - s2.w) + 0.0500000007450580596923828125);
                    totalCol += s1.xyz * w1 + s2.xyz * w2;
                    totalWeight += w1 + w2;
                }
                return half4(totalCol / max(totalWeight, 1e-5), centerColor.w);
            }
            ENDHLSL
        }

        // pass 1:远近 gather(dump `_85`)
        Pass
        {
            Name "DoFGatherFarNear"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragFarNear

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            SAMPLER(sampler_BlitTexture);

            float4 _LianDoFParams;   // x=minBlurRadius, y=radiusMult, z=cocOffset, w=aspect

            half4 FragFarNear(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float minBlurRadius = _LianDoFParams.x * _LianDoFParams.y;

                half4 centerColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);
                float2 cocMax = max(centerColor.ww, float2(0.0, 0.00999999977648258209228515625));
                float3 coc = float3(cocMax.x, cocMax.y, 0.0);
                float3 farSceneCol = coc.x * centerColor.xyz;

                // cocAbsVal / FarCocAreaFactor(dump 线 4084-4091)
                float cocAbsVal = saturate(abs(centerColor.w) - (_LianDoFParams.z - 1.0));
                float farCocAreaFactor = min(1.0 / (coc.y * coc.y * 3.1415927410125732421875), 5.092957973480224609375);
                bool isInFocus = 0.0 >= centerColor.w;
                float farCoCAbsRadius = isInFocus ? 0.0 : cocAbsVal;

                // shiftCocFactor(dump 线 4092-4104)
                float shiftCoc = saturate((centerColor.w + minBlurRadius) * 0.5);
                shiftCoc = shiftCoc * shiftCoc * (3.0 - 2.0 * shiftCoc);
                float oneMinusShift = 1.0 - shiftCoc;

                float cocFactor = shiftCoc * farCoCAbsRadius * farCocAreaFactor;
                float3 wSceneCenterCoc = farSceneCol * cocFactor;
                float rcocFactor = farCoCAbsRadius * oneMinusShift * farCocAreaFactor;
                float3 rwSceneCenterCoc = farSceneCol * rcocFactor;
                float farCoCAbsRadius2 = (centerColor.w > 0.0 ? 1.0 : 0.0) * cocAbsVal;

                // blurR / rBlur / lod radius(dump 线 4106-4119)
                float2 blurR = minBlurRadius * float2(0.4000000059604644775390625, 0.5);
                float rBlur = 1.0 / exp2(ceil(log2(blurR.x)));
                float currentLodRadius = _LianDoFParams.y * 0.5;
                float aspect = _LianDoFParams.w * _LianDoFParams.x;

                float3 nearColorBuffer = rwSceneCenterCoc;
                float3 farColorBuffer = wSceneCenterCoc;
                float rcocSum = rcocFactor;
                float cocSum = cocFactor;
                float ccocSum = 0.0;

                // 双层环采样(dump 线 4123-4175)
                for (uint layer = 0u; layer < 2u; ++layer)
                {
                    uint stopNum = 4u + 4u * layer;
                    for (uint j = 0u; j < stopNum; ++j)
                    {
                        float angle = (float(layer) * 0.5 + float(j)) * 3.1415927410125732421875 / float(stopNum);
                        float2 dir = float2(cos(angle), sin(angle));
                        float2 offset = currentLodRadius * dir;
                        offset.y *= aspect;
                        half4 s1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + offset);
                        half4 s2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv - offset);

                        float fw1 = clamp((abs(s1.w) - float(layer) * blurR.y) * rBlur + 0.5, 0.0, 1.0);
                        float fw2 = clamp((abs(s2.w) - float(layer) * blurR.y) * rBlur + 0.5, 0.0, 1.0);
                        float3 cw1 = s1.xyz * max(s1.w, 0.0);
                        float3 cw2 = s2.xyz * max(s2.w, 0.0);
                        fw1 = isInFocus ? 0.0 : fw1;
                        fw2 = isInFocus ? 0.0 : fw2;

                        float centerCocHalf = saturate((centerColor.w + blurR.x) * 0.5);
                        float smooth = centerCocHalf * centerCocHalf * (3.0 - 2.0 * centerCocHalf);
                        float oneMinusSmooth = 1.0 - smooth;

                        // sample1:远 + 近 buffer
                        float wFar = farCocAreaFactor * fw1 * smooth;
                        farColorBuffer += cw1 * wFar;
                        cocSum += wFar;
                        float wNear = farCocAreaFactor * fw1 * oneMinusSmooth;
                        nearColorBuffer += cw1 * wNear;
                        rcocSum += wNear;

                        // sample2
                        wFar = farCocAreaFactor * fw2 * smooth;
                        farColorBuffer += cw2 * wFar;
                        cocSum += wFar;
                        wNear = farCocAreaFactor * fw2 * oneMinusSmooth;
                        nearColorBuffer += cw2 * wNear;
                        rcocSum += wNear;

                        ccocSum += 2.0 * farCoCAbsRadius2;
                    }
                }

                // 归一化 + 混合(dump 线 4205-4236)
                float r = max(minBlurRadius * 1.25, 0.00999999977648258209228515625);
                float curFactor = 1.0 / min(1.0 / (r * r * 3.1415927410125732421875), 5.092957973480224609375);
                float alpha = clamp(curFactor * cocSum * 0.039999999105930328369140625
                    + (cocSum == 0.0 ? 1.0 : 0.0), 0.0, 1.0);

                float3 normalizedFar = (cocSum > 0.001000000047497451305389404296875) ? farColorBuffer / cocSum : 0.0;
                float3 normalizedNear = (rcocSum > 0.001000000047497451305389404296875) ? nearColorBuffer / rcocSum : 0.0;
                float3 finalCol = lerp(normalizedFar, normalizedNear, alpha);

                float farAlpha = ((cocSum + rcocSum) > 0.0) ? (ccocSum * 0.039999999105930328369140625) : 0.0;
                finalCol /= max(alpha, 0.001000000047497451305389404296875);
                return half4(farAlpha * finalCol.x, farAlpha * finalCol.y, farAlpha * finalCol.z, 1.0 - farAlpha);
            }
            ENDHLSL
        }
    }
}
