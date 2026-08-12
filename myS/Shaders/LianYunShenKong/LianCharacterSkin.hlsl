#ifndef LIAN_CHARACTER_SKIN_INCLUDED
#define LIAN_CHARACTER_SKIN_INCLUDED

// 皮肤 pass 16(dump `_85`,线 2692-2987):diffuse only + profile MRT。
// 主光 1/π·ndotl·color·shadow、天空光 1/π·ndotSky·skyColor·ao、高度 GI、4 盏 tile 附加光。

#include "LianCharacterVertex.hlsl"
#include "LianCharacterGI.hlsl"
#include "LianCharacterLighting.hlsl"

struct LianSkinOutput
{
    half4 diffuse : SV_Target0;   // _LianSkinDiffuseTex: rgb=finalRadiance, a=1-alpha
    half profile : SV_Target1;    // _LianSkinProfileTex: a=1-alpha
};

/// 单盏 tile 灯皮肤贡献(dump 线 2839-2858)
float3 LianSkinTileLight(int lightIndex, float3 positionWS, float3 normalWS, float shadowMul)
{
    float3 lightDir = LianLightDir(lightIndex, positionWS);
    float lenSq = max(dot(lightDir, lightDir), 1.1754943508222875079687365372222e-38);
    float3 lightDirN = lightDir * rsqrt(lenSq);
    float atten = LianLightDistanceAtten(lightIndex, lenSq)
                * LianLightAngleAtten(lightIndex, dot(_LianLightSpotDir[lightIndex].xyz, lightDirN));
    float ndotl = max(dot(normalWS, lightDirN), 0.0);
    return max(0.3183098733425140380859375 * ndotl * shadowMul * _LianLightColor[lightIndex].xyz * atten, 0.0);
}

LianSkinOutput LianSkinFrag(LianCharacterVaryings input)
{
    LianSkinOutput output;
    float4 uv = input.uv;

    // 法线选择(dump 线 2694-2715):param.y = profile;uv.x≥0.5 用 _NormalSelectRight
    float profileIndex = SAMPLE_TEXTURE2D(_ParamMap, sampler_ParamMap, uv.xy).y;
    bool isRight = uv.x >= 0.5;
    float isSelect = isRight ? _NormalSelectRight : _NormalSelectLeft;

    float4 normalEnc = SAMPLE_TEXTURE2D_LOD(_NormalMap, sampler_NormalMap, uv.xy, _TextureMipBias);
    float3 n1 = float3(normalEnc.x * 2.0 - 1.0, normalEnc.y * 2.0 - 1.0, 0.0);
    n1.z = sqrt(max(1.0 - dot(n1.xy, n1.xy), 0.0));
    float3 n2 = float3(normalEnc.z * 2.0 - 1.0, normalEnc.w * 2.0 - 1.0, 0.0);
    n2.z = sqrt(max(1.0 - dot(n2.xy, n2.xy), 0.0));
    float3 normalTS = lerp(n1, n2, isSelect);

    // TBN → normalWS(dump 线 2716-2724)
    float3 normalWS = normalize(normalTS.x * input.tangentWS.xyz
                              + normalTS.y * input.binormalWS.xyz
                              + normalTS.z * input.normalWS.xyz);

    // bakedGI(dump 线 2725-2739)
    half3 bakedGI = LianCharacterBakedGI(normalWS);

    // screenUV + shadowAO(dump 线 2740-2755;SV_Position 与 RT uv 同原点,直接除 _ScreenParams)
    float2 screenUV = input.positionCS.xy / _ScreenParams.xy;
    float4 shadowAO = SAMPLE_TEXTURE2D_X(_LianShadowAOTex, sampler_LianShadowAOTex, screenUV);
    float shadow = lerp(1.0, shadowAO.x, _ShadowStrength);
    bool shadowVisible = 0.001000000047497451305389404296875 < shadow;

    // 主光(dump 线 2756-2767)
    float ndotl = max(dot(normalWS, _MainLightDir), 0.0);
    float3 mainRadiance = ndotl * _MainLightColor.xyz * shadow * 0.3183098733425140380859375;
    mainRadiance = shadowVisible ? mainRadiance : 0.0;

    // 天空光(dump 线 2768-2778)
    float ndotSky = max(dot(normalWS, _SkyLightDir.xyz), 0.0);
    float3 skyRadiance = ndotSky * _SkyLightColor.xyz * 0.3183098733425140380859375;
    float3 lightRadiance = skyRadiance * shadowAO.a + mainRadiance;

    // 高度 GI(dump 线 2779-2802)
    float heightFactor = clamp(input.positionWS.y - _HeightOffset, -1.0, 1.0) * _HeightFactor + 1.0;
    float3 bakedGIH = heightFactor * bakedGI;
    float bakedGIIlluminance = dot(bakedGIH,
        float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 bakedGIOff = saturate(bakedGIH + _BakedGIOffset.xyz);
    float3 hAffectBakedGI = lerp(bakedGIH, bakedGIOff, _GILerp);
    float3 bakedGI_R = lerp(bakedGIIlluminance, hAffectBakedGI, _BakedGIBlend) * _BakedGIStrength;
    lightRadiance += bakedGI_R * shadowAO.a;

    // ---- tile 灯光(dump 线 2803-2968)----
    float2 tileUV = (input.positionWS.xz - _LianTileGridParams.xy) / _LianTileGridParams.zw;
    float4 tileIndices = SAMPLE_TEXTURE2D_X(_LianTileLightIndexTex, sampler_LianTileLightIndexTex, tileUV);
    float4 lightIndexF = floor(tileIndices * 255.0 + 0.5);

    // 4 盏:shadowSel = dot(shadowAO, _LianLightShadowSel[idx])(dump `_63`)
    float3 addRadiance = 0.0;
    for (int k = 0; k < 4; ++k)
    {
        float idxF = lightIndexF[k];
        if (!(idxF < 30.0))
            continue;
        int lightIndex = int(idxF);
        float shadowSel = dot(shadowAO, _LianLightShadowSel[lightIndex]);
        float shadowMul = 1.0 - shadowSel;
        if (0.001000000047497451305389404296875 < shadowMul)
            addRadiance += LianSkinTileLight(lightIndex, input.positionWS, normalWS, shadowMul);
    }

    float3 finalRadiance = lightRadiance + addRadiance;
    float oneMinusAlpha = 1.0 - profileIndex;
    output.diffuse = half4(finalRadiance.x, finalRadiance.y, finalRadiance.z, oneMinusAlpha);
    output.profile = half(oneMinusAlpha);
    return output;
}

#endif // LIAN_CHARACTER_SKIN_INCLUDED
