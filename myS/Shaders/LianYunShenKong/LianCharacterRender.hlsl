#ifndef LIAN_CHARACTER_RENDER_INCLUDED
#define LIAN_CHARACTER_RENDER_INCLUDED

// 角色最终着色 pass 20(dump `_134`,线 3181-3736):
// albedo/decal/tint/normal/detail 混合 → SH GI → _LianShadowAOTex + _LianSSSTex →
// 本地 D_GGX/Vis_SmithJointApprox/F_Schlick(dump 数学,不复用 URP BRDF)→ EnvCube 反射 →
// tile 附加光(含 MobileSpecularGGX 高光)→ 雾体积(LianCharacterFog.hlsl)→
// alpha = lerp(1, _OutputAlpha, _AlphaMix)。

#include "LianCharacterVertex.hlsl"
#include "LianCharacterGI.hlsl"
#include "LianCharacterLighting.hlsl"
#include "LianCharacterFog.hlsl"

float Pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

// dump `_116`:GGX D 分母参数与 Vis 粗糙度(max(r², 0.01) / max(r², 0.1))
void LianGGXParams(float roughness, out float denomA, out float denomB, out float visRough)
{
    float r2 = roughness * roughness;
    float a2 = max(r2, 0.00999999977648258209228515625);
    float visR = max(r2, 0.100000001490116119384765625);
    denomA = a2 - 1.0 / a2;
    denomB = 1.0 / a2;
    visRough = visR;
}

float LianD_GGX(float ndoth, float denomA, float denomB)
{
    float nd2 = min(ndoth, 0.999000012874603271484375) * min(ndoth, 0.999000012874603271484375);
    float d = 1.0 / (nd2 * denomA + denomB);
    d = min(d, 10.0);
    return d * d * 0.3183098733425140380859375;
}

float LianVis_SmithJointApprox(float ndotv, float ndotl, float visRough)
{
    float a = 1.0 - visRough;
    float v1 = ndotv * a + visRough;
    float l1 = ndotl * a + visRough;
    float v = 0.5 / (ndotl * v1 + ndotv * l1);
    return min(v, 10.0);
}

float LianF_Schlick(float vdoth, float F0, float F90)
{
    float fc = Pow5(1.0 - vdoth);
    return F0 * (1.0 - fc) + F90 * fc;
}

// 单盏 tile 灯(render-object,dump 线 3455-3540:漫反射 + MobileSpecularGGX 高光)
float3 LianRenderTileLight(int lightIndex, float3 positionWS, float3 normalWS, float3 viewDirWS,
    float shadowMul, float denomA, float denomB, float visRough, float F0, float roughness)
{
    float3 lightDir = LianLightDir(lightIndex, positionWS);
    float lenSq = max(dot(lightDir, lightDir), 1.1754943508222875079687365372222e-38);
    float3 lightDirN = lightDir * rsqrt(lenSq);
    float atten = LianLightDistanceAtten(lightIndex, lenSq)
                * LianLightAngleAtten(lightIndex, dot(_LianLightSpotDir[lightIndex].xyz, lightDirN));
    float ndotl = max(dot(normalWS, lightDirN), 0.0);
    float3 addRadiance = atten * ndotl * _LianLightColor[lightIndex].xyz;

    // 高光(MobileSpecularGGX:vis = roughness·0.25 + 0.25)
    float3 halfDir = normalize(lightDirN + viewDirWS);
    float ndoth = max(dot(normalWS, halfDir), 0.0);
    float vis = roughness * 0.25 + 0.25;
    float spec = LianD_GGX(ndoth, denomA, denomB) * vis * F0;
    float3 addSpecular = lerp(0.0, addRadiance * spec, ndotl > 0.0 ? 1.0 : 0.0) * shadowMul;
    return addRadiance + addSpecular;
}

half4 LianCharacterFrag(LianCharacterVaryings input) : SV_Target
{
    float4 uv = input.uv;

    // metallic/roughness(dump 线 3183-3185)
    float2 metallicRoughness = SAMPLE_TEXTURE2D(_ParamMap, sampler_ParamMap, uv.xy).xz;
    bool isRight = uv.x >= 0.5;
    float isSelect = isRight ? _NormalSelectRight : _NormalSelectLeft;

    // albedo 混合(dump 线 3186-3230)
    float4 albedoBase = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, uv.xy, _TextureMipBias);
    float2 uvOff = uv.xy + float2(-0.5, -0.4709999859333038330078125);
    float2 outside = float2(abs(uvOff.x) >= 0.100000001490116119384765625 ? 1.0 : 0.0,
                            abs(uvOff.y) >= 0.0489999987185001373291015625 ? 1.0 : 0.0);
    float isOutsideRect = max(outside.x, outside.y);

    float4 albedoDetail = SAMPLE_TEXTURE2D_LOD(_DetailTex, sampler_DetailTex, uv.zw, _TextureMipBias);
    float3 blendedAlbedo = lerp(albedoBase.xyz, albedoDetail.xyz, isSelect * albedoDetail.w);
    float3 albedo = blendedAlbedo * _ColorTint.xyz;
    float3 albedoM = lerp(_AlbedoMColor.xyz, albedo, albedoBase.w);
    float3 albedoMM = lerp(albedo, albedoM, _AlbedoMMix);
    float3 albedoFinal = lerp(albedoMM, albedo, isOutsideRect);
    float brightM = lerp(1.0, albedoBase.w, isOutsideRect * _BrightM);
    float3 albedoBright = albedoFinal * brightM;

    float4 decal = SAMPLE_TEXTURE2D(_DecalTex, sampler_DecalTex, uv.xy);
    float3 albedoDecal = lerp(albedoBright, decal.xyz * _DecalColor.xyz, decal.w * _DecalColor.w);

    float4 tintMask = SAMPLE_TEXTURE2D(_TintMask, sampler_TintMask, uv.xy);
    float tintDot = dot(tintMask, _TintMaskWeights);
    float3 tintControl = lerp(1.0, _TintControlBase.xyz, tintDot);
    float3 albedoFinal2 = albedoDecal * tintControl;

    // normal(dump 线 3231-3252)
    float2 normalEnc = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv.xy).xy;
    float2 detailNormalEnc = SAMPLE_TEXTURE2D(_DetailNormalMap, sampler_DetailNormalMap, uv.zw).xy;
    float3 n1 = float3(normalEnc.x * 2.0 - 1.0, normalEnc.y * 2.0 - 1.0, 0.0);
    n1.z = sqrt(max(1.0 - dot(n1.xy, n1.xy), 0.0));
    float3 dn = float3(detailNormalEnc.x * 2.0 - 1.0, detailNormalEnc.y * 2.0 - 1.0, 0.0);
    dn.z = sqrt(max(1.0 - dot(dn.xy, dn.xy), 0.0));
    float3 normalTS = lerp(n1, dn, isSelect * albedoDetail.w);

    // viewDir / normalWS(dump 线 3253-3268)
    float3 viewDirWS = normalize(float3(input.normalWS.w, input.tangentWS.w, input.binormalWS.w));
    float3 normalWS = normalize(normalTS.x * input.tangentWS.xyz
                              + normalTS.y * input.binormalWS.xyz
                              + normalTS.z * input.normalWS.xyz);

    // bakedGI(dump 线 3269-3281)
    half3 bakedGI = LianCharacterBakedGI(normalWS);

    // shadow/SSS(dump 线 3282-3297)
    float2 screenUV = input.positionCS.xy / _ScreenParams.xy;
    float4 shadowAO = SAMPLE_TEXTURE2D_X(_LianShadowAOTex, sampler_LianShadowAOTex, screenUV);
    float shadow = lerp(1.0, shadowAO.x, _ShadowStrength);
    float3 sssLighting = SAMPLE_TEXTURE2D_X(_LianSSSTex, sampler_LianSSSTex, screenUV).xyz;

    // GGX 参数(dump 线 3305-3310)
    float denomA, denomB, visRough;
    LianGGXParams(metallicRoughness.x, denomA, denomB, visRough);
    float F0 = metallicRoughness.y * _Specular * 0.07999999821186065673828125;
    float F90 = saturate(metallicRoughness.y * _Specular * 4.0);

    // 主光(dump 线 3298-3340)
    float ndotv = max(dot(normalWS, viewDirWS), 0.0) + 9.9999997473787516355514526367188e-06;
    float ndotl = max(dot(normalWS, _MainLightDir), 0.0);
    float3 halfDir = normalize(viewDirWS + _MainLightDir);
    float vdoth = max(dot(viewDirWS, halfDir), 0.0);
    float ndoth = max(dot(normalWS, halfDir), 0.0);

    float D = LianD_GGX(ndoth, denomA, denomB);
    float G = LianVis_SmithJointApprox(ndotv, ndotl, visRough);
    float F = LianF_Schlick(vdoth, F0, F90);
    float3 specularColor = shadow * lerp(0.0, ndotl * _MainLightColor.xyz * (D * G * F), ndotl > 0.0 ? 1.0 : 0.0);
    float3 directLighting = albedoFinal2 * sssLighting + specularColor;

    // 天空光高光(dump 线 3341-3390)
    float ndotSl = max(dot(normalWS, _SkyLightDir.xyz), 0.0);
    float3 halfDirSL = normalize(viewDirWS + _SkyLightDir.xyz);
    float vdotHSL = max(dot(viewDirWS, halfDirSL), 0.0);
    float ndotHSL = max(dot(normalWS, halfDirSL), 0.0);
    float D1 = LianD_GGX(ndotHSL, denomA, denomB);
    float G1 = LianVis_SmithJointApprox(ndotv, ndotSl, visRough);
    float F1 = LianF_Schlick(vdotHSL, F0, F90);
    float3 skySpecular = lerp(0.0, ndotSl * _SkyLightColor.xyz * (D1 * G1 * F1), ndotSl > 0.0 ? 1.0 : 0.0);
    float3 directAndSky = directLighting + skySpecular * shadowAO.a;

    // 环境反射(dump 线 3391-3416)
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    float lod = metallicRoughness.x * (-metallicRoughness.x * 0.699999988079071044921875 + 1.7000000476837158203125) * 6.0;
    float4 env = SAMPLE_TEXTURECUBE_LOD(_EnvCube, sampler_EnvCube, reflectDir, lod);
    float envW = max(lerp(1.0, env.w, _EnvAlphaLerp), 0.0);
    envW = pow(envW, _EnvPower) * _EnvIntensity;
    float3 envGI = bakedGI * env.rgb * envW;
    float3 specularGI = F0 * envGI * _BakedGIStrength + directAndSky;

    // ---- tile 灯光(含高光,dump 线 3417-3590)----
    float2 tileUV = (input.positionWS.xz - _LianTileGridParams.xy) / _LianTileGridParams.zw;
    float4 tileIndices = SAMPLE_TEXTURE2D_X(_LianTileLightIndexTex, sampler_LianTileLightIndexTex, tileUV);
    float4 lightIndexF = floor(tileIndices * 255.0 + 0.5);

    float3 addSpecular = 0.0;
    for (int k = 0; k < 4; ++k)
    {
        float idxF = lightIndexF[k];
        if (!(idxF < 30.0))
            continue;
        int lightIndex = int(idxF);
        float shadowSel = dot(shadowAO, _LianLightShadowSel[lightIndex]);
        float shadowMul = 1.0 - shadowSel;
        if (0.001000000047497451305389404296875 < shadowMul)
            addSpecular += LianRenderTileLight(lightIndex, input.positionWS, normalWS, viewDirWS,
                shadowMul, denomA, denomB, visRough, F0, metallicRoughness.x);
    }

    float3 finalLightColor = specularGI + addSpecular;
    finalLightColor = LianApplyFog(finalLightColor, input.positionWS);

    float alpha = lerp(1.0, _OutputAlpha, _AlphaMix);
    return half4(finalLightColor.x, finalLightColor.y, finalLightColor.z, alpha);
}

#endif // LIAN_CHARACTER_RENDER_INCLUDED
