// NPRCharacter/NPRCharacterLighting.hlsl
// skin/face 100% 一致的共享光照子函数(主光管线各自实现以保 asm 顺序可追溯,见 SkinLighting.hlsl / FaceLighting.hlsl)。
// 附加光循环的共用子函数(切线解码/胶囊辐照度/GGX)也在此。
#ifndef NPRCHARACTER_LIGHTING_INCLUDED
#define NPRCHARACTER_LIGHTING_INCLUDED

#include "NPRCharacterInput.hlsl"
#include "NPRCharacterVertex.hlsl"
#include "NPRCharacterGI.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// ============================================================================
// 通用工具
// ============================================================================

// D_GGX(skin 394-400 / face 523-529):无 PI 归一化、denom^2 分母、ne 保护分支照抄
float CharacterD_GGX(float roughnessSqrSqr, float ndoth)
{
    float denom = (roughnessSqrSqr * ndoth - ndoth) * ndoth + 1.0;
    denom *= denom;
    return (roughnessSqrSqr != denom) ? roughnessSqrSqr / denom : 1.0;
}

// GGX 项(skin 394-407 / face 523-536,clampMax=20):D / (ndotv*2 + roughnessSqr + 0.0001),
// clamp(term*0.5 - 0.0001, 0, clampMax)
float CharacterGGXTerm(float roughnessSqr, float ndotH, float ndotv, float clampMax)
{
    float d = CharacterD_GGX(roughnessSqr * roughnessSqr, ndotH);
    float term = d / (ndotv * 2.0 + roughnessSqr + 0.0001);
    return clamp(term * 0.5 - 0.0001, 0.0, clampMax);
}

// specularGGXReflectanceApprox(face 542-570,来源注释 boksajak/brdf.h)
// 输入 specularColor(仅用于占位,本实现为有理分式,与 specularF0 无关),alpha, ndotv;输出 (approxA, approxB)
// 常数逐条照抄 asm(注意 553/566 的 -16.3174/9.2295 与 20.3225 为指令值)
float2 CharacterSpecularGGXReflectanceApprox(float3 specularF0, float alpha, float ndotv)
{
    float ndotv2 = ndotv * ndotv;
    float ndotv3 = ndotv2 * ndotv;
    float alpha2 = alpha * alpha;
    float alpha4 = alpha2 * alpha2;
    float alpha6 = alpha2 * alpha4;
    // 第一组有理分式(face 547-559)
    float a0 = 3.3271 * ndotv + 0.0365;
    float a1 = -9.0476 * ndotv + 9.0632;
    float numA = a0 + a1 * alpha;
    float b0 = 3.5968 * ndotv2 - 1.3677 * ndotv3 + 1.0;
    float b1 = -16.3174 * ndotv2 + 9.044 + 9.2295 * ndotv3;
    float b2 = 5.5659 + 19.7886 * ndotv2 - 20.2123 * ndotv3;
    float denA = b0 + b1 * alpha + b2 * alpha6;
    float approxA = numA / denA;
    // 第二组有理分式(face 560-570)
    float c0 = -1.2851 * ndotv + 0.9904;
    float c1 = 1.2968 - 0.7559 * ndotv;
    float numB = c0 + c1 * alpha;
    float d0 = 2.9234 * ndotv + 59.4188 * ndotv3 + 1.0;
    float d1 = 20.3225 - 27.0302 * ndotv + 222.592 * ndotv3;
    float d2 = 626.13 * ndotv + 316.627 * ndotv3 + 121.563;
    float denB = d0 + d1 * alpha + d2 * alpha6;
    float approxB = numB / denB;
    return float2(approxA, approxB);
}

// 场景阴影(skin 301-309 / face 351-359):
//   _SCENE_SHADOW_TEX 下采样 _CharacterShadowTex(原 ld_indexable 直读改采样),返回 (curSceneShadow, selfShadow)
//   face 的原始 asm 为 t2.zwxy 读 texel.z/.w —— 对 RG 阴影纹理该 swizzle 恒为 (0,1),
//   与 skin 的 r/g 通道注释(皮肤文件头:"r通道是场景阴影 g通道是角色自阴影")矛盾,按 skin/cloth 统一读 .rg。
//   #else 用 URP 主光实时阴影(Shadows.hlsl:346/330)。
float2 GetCharacterSceneShadow(float4 positionCS, float3 positionWS)
{
    float sceneShadow;
    float selfShadow = 1.0;
#if defined(_SCENE_SHADOW_TEX)
    float2 screenUV = GetNormalizedScreenSpaceUV(positionCS);
    float2 shadowTex = SAMPLE_TEXTURE2D(_CharacterShadowTex, sampler_LinearClamp, screenUV).rg;
    sceneShadow = lerp(1.0, shadowTex.r, _ShadowTexIntensity);   // asm 306-307
    selfShadow = shadowTex.g;
#else
    sceneShadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(positionWS));
#endif
    return float2(lerp(sceneShadow, 1.0, _SceneShadowMix), selfShadow);   // asm 308-309
}

// 背光 ramp 偏移(skin 319-321 / face 373-375):clamp(ndotlt + _BackLightBias * _BackLightControl, -1, 1)
float ApplyCharacterBackLight(float ndotlt)
{
    return clamp(ndotlt + _BackLightBias * _BackLightControl, -1.0, 1.0);
}

// 亮度饱和度增强(skin 411-417 / face 596-602;lerp 系数 >1,照抄)
float3 EnhanceCharacterSaturation(float3 c)
{
    float i = CharacterLuminance(c);
    float boost = clamp(i - 0.5, 0.0, 0.5);
    return lerp(i, c, boost * boost + 1.0);
}

// 边缘光(skin 418-446;face 的 603-645 含 faceControl 修正,在 FaceLighting.hlsl 内联实现)
// 输入:normal(SDF 修正后的法线/法线贴图法线), rawNdotV(未钳制), objectDir, AO, selfShadow, diffuseColor
float3 GetCharacterRimLight(float3 normal, float rawNdotV, float2 objectDir, float AO, float selfShadow, float3 diffuseColor)
{
    float3 rimLightColor = 0;
    if (_RimColor.a > 0.01)   // rimLightOn(skin asm 418)
    {
        float3 camVector = UNITY_MATRIX_V._13_23_33;
        float3 camRimDir = normalize(cross(camVector, _RimDir.xyz));   // asm 419-424
        float2 reverseNdotV = float2(1.0 - abs(rawNdotV), 0.4 - abs(rawNdotV));   // asm 425
        float r0 = 0.8 - _RimRange * 0.6;                                       // asm 426
        float r1 = 0.9 - _RimRange * 0.4;
        float rimFactor = smoothstep(0.0, 1.0, saturate((reverseNdotV.x - r0) / (r1 - r0)));   // asm 427-433
        float3 rimLight = _RimColor.rgb * _RimColor.a * rimFactor;             // asm 434-435
        float camRimFactor = saturate(dot(objectDir, camRimDir.xz) + 1.0);     // asm 436-437
        float rimShadow = min(AO, min(camRimFactor, selfShadow));              // asm 438-439
        float ndotCamRimDir = saturate(dot(camRimDir, normal));                // asm 441
        rimLightColor = rimLight * rimShadow * ndotCamRimDir * lerp(0.25, diffuseColor, _RimFresnelMix);   // asm 442-445
    }
    return rimLightColor;   // asm 446: rimLightOn && rimLightColor
}

// ============================================================================
// 附加光循环共用子函数(asm skin 609-695 / face 777-862 同源)
// ============================================================================

// 切线半八面体解码(asm skin 615-625):packed.x = X(带符号), packed.y = P = a+b
// 精确互逆的 C# 编码(ClothStylizedLight.GetData,由本解码逆推):
//   L1 = |tx|+|ty|+|tz|; X = sign(ty)*(1 + (tx-tz)/L1)/2; P = (tx+tz)/L1
float3 DecodeCharacterTangent(float2 packed)
{
    float pp = packed.y * 0.5 + 0.5;                 // asm 615
    float a = pp - abs(packed.x);                    // asm 616
    float b = packed.y - a;                          // asm 617
    float y = (packed.x >= 0.0) ? max(1.0 - abs(a) - abs(b), 0.0) : -max(1.0 - abs(a) - abs(b), 0.0);  // asm 618-622
    return normalize(float3(b, y, a));               // asm 623-625
}

// 胶囊辐照度(asm skin 639-667 / face 808-834,UE4 方程 16;swizzle 逐条照抄)
// lightToPos = 表面指向光源;tangent = 胶囊方向;返回辐照度,正交方向由 orthoDir 输出
float GetCharacterCapsuleIrradiance(float3 lightToPos, float3 curLightDir, float3 tangent, float capsuleLength,
                                    out float3 orthoDir)
{
    float3 shift1 = lightToPos - 0.5 * tangent.zxy * capsuleLength;   // asm skin 640-641 / face 808-809
    float3 shift2 = lightToPos + 0.5 * tangent.zxy * capsuleLength;   // asm skin 642 / face 810
    float len1 = length(shift1);                                      // asm skin 643-644 / face 811-812
    float len2 = length(shift2);                                      // asm skin 645-646 / face 813
    float dot12 = dot(shift1, shift2);                                // asm skin 647 / face 814
    // 正交基(asm skin 651-660 / face 818-827,逐 swizzle 照抄)
    float3 biAuxRaw = float3(
        tangent.z * curLightDir.y - curLightDir.x * tangent.x,
        tangent.x * curLightDir.z - curLightDir.y * tangent.y,
        tangent.y * curLightDir.x - curLightDir.z * tangent.z);
    float3 biAuxDir = normalize(biAuxRaw);
    float3 orthoRaw = float3(
        biAuxDir.z * tangent.y - tangent.x * biAuxDir.x,
        biAuxDir.x * tangent.z - tangent.y * biAuxDir.y,
        biAuxDir.y * tangent.x - tangent.z * biAuxDir.z);
    orthoDir = normalize(orthoRaw);
    float dot1 = dot(orthoDir, shift1) / len1;                        // asm skin 661-662 / face 828-829
    float dot2 = dot(orthoDir, shift2) / len2;                        // asm skin 663-664 / face 830-831
    float lightIrradiance = saturate((dot1 + dot2) * 0.5) / ((len1 * len2 + dot12) * 0.5 + 1.0);  // asm skin 665-667 / face 832-834
    return lightIrradiance;
}

#endif // NPRCHARACTER_LIGHTING_INCLUDED
