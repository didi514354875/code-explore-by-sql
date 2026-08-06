// NPRCloth/ClothLighting.hlsl
// 材质解码(Step 3,asm PS 0-53)+ 主光漫反射 ramp 管线/高光/rim/gEnv/IBL(Step 6,asm 397-680)+ 附加光源循环(Step 7,asm 681-1140)。
// 命名沿用 asm 注释语义;与计划公式冲突处一律以 asm 指令为准(已在代码内标注)。
#ifndef NPRCLOTH_CLOTH_LIGHTING_INCLUDED
#define NPRCLOTH_CLOTH_LIGHTING_INCLUDED

#include "ClothInput.hlsl"
#include "ClothVertex.hlsl"
#include "ClothGI.hlsl"
#include "ClothRain.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// ============================================================================
// 通用工具
// ============================================================================

// D_GGX(asm 530-536):无 PI 归一化、denom^2 分母、ne 保护分支照抄
float ClothD_GGX(float roughnessSqrSqr, float ndoth)
{
    float denom = (roughnessSqrSqr * ndoth - ndoth) * ndoth + 1.0;
    denom *= denom;
    return (roughnessSqrSqr != denom) ? roughnessSqrSqr / denom : 1.0;
}

// specularGGXReflectanceApprox(asm 634-661,来源注释 boksajak/brdf.h)
// 输入 curSpecularColor(仅用于占位,本实现为有理分式,与 specularF0 无关),alpha, ndotv;输出 (approxA, approxB)
// 常数逐条照抄 asm(注意 645 的 -16.3174/9.2295 与 657 的 20.3225 为指令值)
float2 SpecularGGXReflectanceApproxCloth(float3 specularF0, float alpha, float ndotv)
{
    float ndotv2 = ndotv * ndotv;                 // asm 544(r13.x)
    float ndotv3 = ndotv2 * ndotv;                // asm 635
    float alpha2 = alpha * alpha;                 // asm 634
    float alpha4 = alpha2 * alpha2;               // asm 636
    float alpha6 = alpha2 * alpha4;               // asm 637
    // 第一组有理分式(asm 638-650)
    float a0 = 3.3271 * ndotv + 0.0365;           // asm 639
    float a1 = -9.0476 * ndotv + 9.0632;          // asm 640
    float numA = a0 + a1 * alpha;                 // asm 642
    float b0 = 3.5968 * ndotv2 - 1.3677 * ndotv3 + 1.0;          // asm 644(r13.xzw = (ndotv², ndotv³, 1))
    float b1 = -16.3174 * ndotv2 + 9.044 + 9.2295 * ndotv3;      // asm 645(r13.xyz = (ndotv², 9.044, ndotv³))
    float b2 = 5.5659 + 19.7886 * ndotv2 - 20.2123 * ndotv3;     // asm 646-648
    float denA = b0 + b1 * alpha + b2 * alpha6;   // asm 649
    float approxA = numA / denA;                  // asm 650
    // 第二组有理分式(asm 651-661)
    float c0 = -1.2851 * ndotv + 0.9904;          // asm 651
    float c1 = 1.2968 - 0.7559 * ndotv;           // asm 652-654
    float numB = c0 + c1 * alpha;                 // asm 655
    float d0 = 2.9234 * ndotv + 59.4188 * ndotv3 + 1.0;          // asm 656(r13.yzw = (ndotv, ndotv³, 1))
    float d1 = 20.3225 - 27.0302 * ndotv + 222.592 * ndotv3;     // asm 657-658(r13.xyz = (20.3225, ndotv, ndotv³))
    float d2 = 626.13 * ndotv + 316.627 * ndotv3 + 121.563;      // asm 659(r13.yzw = (ndotv, ndotv³, 121.563))
    float denB = d0 + d1 * alpha + d2 * alpha6;   // asm 660
    float approxB = numB / denB;                  // asm 661
    return float2(approxA, approxB);
}

// ============================================================================
// Step 3:材质解码与法线(asm PS 0-53)
// ============================================================================
ClothSurfaceData GetClothSurfaceData(ClothVaryings input, float isFrontFace)
{
    ClothSurfaceData s = (ClothSurfaceData)0;
    s.wetFactor = 0.0;
    s.wetRoughness = 0.01;

    // asm 0-3: 基础色与 PBR 参数
    float4 baseTex = SAMPLE_TEXTURE2D_BIAS(_BaseMap, sampler_LinearRepeat, input.uv, _MipBias);
    float4 baseColor = baseTex * _BaseColor;
    s.baseColor = baseColor.rgb;
    s.baseAlpha = baseColor.a;
    float4 pbr = SAMPLE_TEXTURE2D_BIAS(_PBRParamTex, sampler_LinearRepeat, input.uv, _MipBias);
    s.metallic = pbr.r;
    s.specularScale = pbr.g;
    s.ao = pbr.b;
    s.roughness = 1.0 - pbr.a;

    // asm 4-7: shadowBaseColor = AdjustSaturation(baseColor * _ShadowColorIntensity, _ShadowColorSaturation)
    s.shadowBaseColor = AdjustSaturationCloth(s.baseColor * _ShadowColorIntensity, _ShadowColorSaturation);

    // asm 8-16: 法线解码(采样 swizzle xywz;n.xy = (2*(r*a)-1, 2*g-1),n.z = sqrt(1 - sat(dot)),*_NormalScale)
    float4 ntex = SAMPLE_TEXTURE2D_BIAS(_NormalMap, sampler_LinearRepeat, input.uv, _MipBias);
    float2 nxy = float2(ntex.r * ntex.a * 2.0 - 1.0, ntex.g * 2.0 - 1.0);
    float nz = sqrt(max(1.0 - saturate(dot(nxy, nxy)), 0.0));
    nxy *= _NormalScale;

    // asm 19-49: TBN 构造与切线空间->世界
    //   按 1/length(normalWS) 缩放(asm 30-43);bitangent 用原始叉积乘符号与缩放(等价 URP CreateTangentToWorld)
    float invLen = rsqrt(max(dot(input.normalWS, input.normalWS), 1e-6));
    float3 tNormal = input.normalWS * invLen;
    float3 tTangent = input.tangentWS.xyz * invLen;
    float3 tBitangent = cross(input.normalWS, input.tangentWS.xyz) * input.tangentWS.w * invLen;
    s.normalTWS = normalize(tTangent * nxy.x + tBitangent * nxy.y + tNormal * nz);
    s.normalWS = tNormal;

    // asm 50-53: 背面翻转
    float faceFlip = isFrontFace > 0.0 ? 1.0 : 2.0 * _DoubleSidedFlip - 1.0;
    s.normalTWS *= faceFlip;
    s.normalWS *= faceFlip;

    // asm 237-387: 雨滴湿润(修改 baseColor/shadowBaseColor/roughness/normalTWS)
    ApplyRain(input, s);

    // asm 388-396: 派生颜色
    float k = 0.96 - 0.96 * s.metallic;
    s.diffuseColor = k * s.baseColor;
    s.specularColor = lerp(s.specularScale * 0.04, s.baseColor, s.metallic);
    s.shadowDiffuseColor = k * s.shadowBaseColor;
    s.roughnessSqr = max(s.roughness * s.roughness, 0.0078);
    s.roughnessSqrSqr = s.roughnessSqr * s.roughnessSqr;

    return s;
}

// ============================================================================
// Step 6 与 Step 7 之间的共享状态(对应 asm 中跨段保留的寄存器)
// ============================================================================
struct ClothLightingState
{
    float3 resultDiffuse;        // r18
    float3 styleSpecularColor;   // r23
    float3 curSpecularColor;     // r12
    float3 diffuseColor;         // r11.xyw
    float3 shadowDiffuseColor;   // r3
    float3 diffuseColorMinusHalf;// r0(asm 735:diffuseColor - 0.5)
    float  curSceneShadow;       // r8.w
    float  roughnessSqr;         // r1.y
    float  ndotv;                // r21.x(saturate(dot(normalTWS, viewDirWS)))
    float  metallic;             // r1.x
    float  baseAlphaLerp;        // r1.w(lerp(1, baseColor.a, _BaseAlphaInfluence))
    float  ndotDominant;         // r2.w(dominantOn * dot(dominantSHDir, normalTWS))
    float  reverseNdotVx;        // r22.x(1 - abs(dot(viewDirWS, normalTWS)))
    float3 lightColor;           // r18(主光颜色含强度)
    float3 camVector;            // cb0[6](相机世界前向)
    float3 viewDirWS;            // r6(归一化)
    float2 objectDir;            // r4.yz(xz 平面物体指向)
};

// ============================================================================
// Step 6:主光漫反射 ramp 管线 + 高光 + rim + gEnv + IBL(asm PS 397-680)
// ============================================================================
float3 ClothLighting(ClothVaryings input, ClothSurfaceData s, ClothIndirectLight gi, out ClothLightingState st)
{
    // ---- 主光(asm 397-408) ----
    Light mainLight = GetMainLight();
    float3 lightDir = normalize(lerp(mainLight.direction, _MainLightDirOverride.xyz, _CharacterLightBlend));  // asm 397-398
    float3 lightCol = lerp(mainLight.color, _MainLightColorOverride.rgb, _LightColorOverrideBlend);            // asm 403-404
    float3 lightColor = lightCol;   // 原 *lerp(cb3[3].w, 1, cb0[171].w) 强度项删除:URP color 已含强度
    float rIntensity = ClothLuminance(lightColor);                                                                  // asm 408

    // 相机与物体方向(asm 17-25)
    float3 camVector = UNITY_MATRIX_V._13_23_33;                                        // cb0[6]:相机世界前向
    float2 camXZ = normalize(camVector.xz);
    float2 lightXZ = normalize(lightDir.xz);                                            // asm 399-402
    float camDotLXZ = dot(lightXZ, camXZ);                                              // asm 421-422
    float2 objectDir = normalize(input.positionWS.xz - unity_ObjectToWorld._14_24_34.xz);
    float3 viewDirWS = normalize(input.viewDirWS);                                      // asm 26-29

    // ---- 场景阴影(asm 410-417) ----
    float sceneShadow;
    float shadowTexY = 1.0;      // ShadowTex.y:角色自阴影(_SCENE_SHADOW_TEX 下取 .g,否则恒 1)
#if defined(_SCENE_SHADOW_TEX)
    float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
    float2 shadowTex = SAMPLE_TEXTURE2D(_CharacterShadowTex, sampler_LinearClamp, screenUV).rg;
    sceneShadow = lerp(1.0, shadowTex.r, _ShadowTexIntensity);       // asm 413-415(原 ld 直读改为采样)
    shadowTexY = shadowTex.g;
#else
    // URP 主光实时阴影(Shadows.hlsl:346/330;中等质量即 asm 内联的 Tent5x5)
    sceneShadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(input.positionWS));
#endif
    float curSceneShadow = lerp(sceneShadow, 1.0, _SceneShadowMix);  // asm 416-417

    // ---- 背光补偿(asm 418-446) ----
    float ndotlt = dot(s.normalTWS, lightDir);                        // asm 418
    float yFactor = smoothstep(0.0, 1.0, saturate((0.75 - abs(camVector.y)) * 2.0));   // asm 431-435
    ndotlt += (1.0 - _BackLightControl) * yFactor * saturate(-camDotLXZ) * (0.5 - 0.5 * ndotlt * ndotlt);  // asm 436-443
    ndotlt += _BackLightBias * _BackLightControl;                     // asm 444
    ndotlt = clamp(ndotlt, -1.0, 1.0);                                // asm 445-446

    // ---- ramp 采样(asm 447-463) ----
    float4 rampTex = SAMPLE_TEXTURE2D_LOD(_RampTex, sampler_LinearClamp, float2(ndotlt * 0.5 + 0.5, 0.5), 0.0);
    float rampTexRange = max(rampTex.r, max(rampTex.g, rampTex.b)) - min(rampTex.r, min(rampTex.g, rampTex.b));  // asm 450-454
    // asm 455-460:camVector.y 有 +0.25 后 min 1 的钳制(以指令为准)
    float3 camVectorN = normalize(float3(camVector.x, min(camVector.y + 0.25, 1.0), camVector.z));
    float camRampTexW = SAMPLE_TEXTURE2D_LOD(_RampTex, sampler_LinearClamp, float2(dot(s.normalTWS, camVectorN) * 0.5 + 0.5, 0.5), 0.0).a;

    // ---- radiance 与漫反射合成(asm 464-508,文件头注释 1:1) ----
    float camShadowRadiance = s.ao * shadowTexY * camRampTexW;                     // asm 464-465
    float rampRadiance = saturate(rampTex.w + camShadowRadiance);                  // asm 466
    float rampShadowRadiance = min(rampTex.w, min(s.ao, shadowTexY));              // asm 469-470
    float3 shadowDiffuseScaled = s.shadowDiffuseColor * _ShadowStrength;           // asm 423(r18)
    float3 _2ndShadowDiffuseColor = AdjustSaturationCloth(shadowDiffuseScaled * 0.65, 1.2);  // asm 424-427
    float3 _2ndDiffuseColor = AdjustSaturationCloth(s.diffuseColor, 1.2);          // asm 428-430
    // 注:asm 467-468 的第二操作数是 shadowDiffuseColor*_ShadowStrength(以指令为准)
    float3 combineShadowDiffuseColor = lerp(_2ndShadowDiffuseColor, shadowDiffuseScaled, rampRadiance);
    float3 curDiffuseColor = lerp(combineShadowDiffuseColor, s.diffuseColor, rampShadowRadiance);  // asm 492-493

    // ---- 环境与光合成(asm 471-491) ----
    float3 shCol = lerp(gi.shColor, 1.0, rampShadowRadiance * _BakedGIStrength);   // asm 471-474
    float3 ambientCol = gi.ndotSky * shCol;                                        // asm 475
    float3 lightColorM = lerp(rIntensity, lightColor, rampShadowRadiance);         // asm 476-477
    float3 mulIntensity = clamp(gi.ambientIntensity, float3(0.0, 1.25, 0.5), float3(1.5, 1.75, 1.5));  // asm 478-479
    float3 lightAndAmbientCol = lightColorM + ambientCol * mulIntensity.x * lerp(1.0, lightCol, _LightColorOverrideBlend);  // asm 480-483
    // 注:asm 487 的 lerp 因子为未映射的 cb0[161].x,按计划用 _BakedGIStrength
    float mulIntensity1 = lerp(min(1.5, gi.ambientIntensity * 0.35 + 0.65), mulIntensity.y, _BakedGIStrength);  // asm 484-487
    float3 ambientAndLightCol = lerp(ambientCol * mulIntensity1 * _EnvIntensity, lightAndAmbientCol * _LightRadianceScale, curSceneShadow);  // asm 488-491

    // ---- resultDiffuse(asm 492-507) ----
    float curDiffuseIntensity = ClothLuminance(curDiffuseColor);                        // asm 494
    float3 rampCurDiffuseColor = lerp(1.0, rampTex.rgb, rampTexRange) * curDiffuseColor;  // asm 495-497
    float normCurDiffuseIntensity = clamp(curDiffuseIntensity / max(ClothLuminance(rampCurDiffuseColor), 0.001), 0.0, 1.5);  // asm 498-503
    float3 diffuseInSceneShadow = lerp(shadowDiffuseScaled, _2ndDiffuseColor, camShadowRadiance);  // asm 504-505
    float3 resultDiffuse = lerp(diffuseInSceneShadow, rampCurDiffuseColor * normCurDiffuseIntensity, curSceneShadow);  // asm 506-507

    // ---- 合成 radiance(asm 508-515) ----
    float3 ambientAndLightDiffuse = ambientAndLightCol * resultDiffuse;            // asm 508
    float combineRadiance = lerp(camShadowRadiance, rampShadowRadiance, curSceneShadow);  // asm 509-510
    float3 ambientAndLightRadiance = ambientAndLightCol * (combineRadiance * 0.5 + 0.5) * lerp(_ShadowStrength, 1.0, combineRadiance);  // asm 511-515

    // ---- 主光高光(asm 516-556) ----
    // 注:asm 517 的 shiftLightDir.y 是 lerp(0.5, lightDir.y, curSceneShadow) 而非 camVector.y(以指令为准)
    float3 shiftLightDir = lightDir * curSceneShadow + float3(camVector.x, lerp(0.5, lightDir.y, curSceneShadow), camVector.z) * 2.0;
    float3 halfDir = normalize(normalize(shiftLightDir) + viewDirWS);               // asm 520-528
    float ndotv = saturate(dot(s.normalTWS, viewDirWS));                            // asm 529
    float ndoth = dot(s.normalTWS, halfDir);                                        // asm 530
    float dGGX = ClothD_GGX(s.roughnessSqrSqr, ndoth);                              // asm 530-536
    float ggxTerm = dGGX / (ndotv * 2.0 + s.roughnessSqr + 0.0001);                 // asm 537-540
    float ggxMax = 1.0 / (s.roughnessSqr * s.roughnessSqr + 0.0001);                // asm 541-542
    float dGGXN = dGGX * ggxMax;                                                    // asm 543
    float2 stylizedLUTUV = float2(lerp(dGGXN, ndotv * ndotv, _SpecStylizedStrength), (1.0 - s.metallic) * s.roughness);  // asm 544-547
    float3 specularStylizedLUT = SAMPLE_TEXTURE2D_LOD(_SpecStylizedLUT, sampler_LinearClamp, stylizedLUTUV, 0.0).rgb;
    float3 styleSpecularColor = s.specularColor * specularStylizedLUT;              // asm 549
    float3 curSpecularColor = lerp(s.specularColor, styleSpecularColor, _SpecStylizedStrength);  // asm 550-551
    float3 specularTerm = styleSpecularColor * clamp(ggxTerm * 0.5 - 0.0001, 0.0, 20.0);  // asm 552-555
    float3 ambientAndLightSpecular = ambientAndLightRadiance * specularTerm;        // asm 556
    float baseAlphaLerp = lerp(1.0, s.baseAlpha, _BaseAlphaInfluence);              // asm 557-558
    float3 ambientAndLightResultCol = ambientAndLightDiffuse * baseAlphaLerp + ambientAndLightSpecular;  // asm 559

    // 亮度饱和度增强(asm 560-566;lerp 系数 >1,照抄)
    float resultIntensity = ClothLuminance(ambientAndLightResultCol);
    float boost = clamp(resultIntensity - 0.5, 0.0, 0.5);
    float3 mainLightResult = lerp(resultIntensity, ambientAndLightResultCol, boost * boost + 1.0);

    // ---- Rim(asm 567-596) ----
    float ndotvRim = dot(viewDirWS, s.normalTWS);                              // asm 574(未 saturate)
    float2 reverseNdotV = float2(1.0 - abs(ndotvRim), 0.4 - abs(ndotvRim));    // asm 575(gEnv 也使用)
    float3 rimLightColor = 0;
    if (_RimColor.a > 0.01)   // rimLightOn(asm 567)
    {
        float3 camRimDir = normalize(cross(camVector, _RimDir.xyz));               // asm 568-573
        float r0 = 0.8 - _RimRange * 0.6;                                          // asm 576
        float r1 = 0.9 - _RimRange * 0.4;
        float rimFactor = smoothstep(0.0, 1.0, saturate((reverseNdotV.x - r0) / (r1 - r0)));  // asm 577-583
        float3 rimLight = _RimColor.rgb * _RimColor.a * rimFactor;                 // asm 584-585
        float camRimFactor = saturate(dot(objectDir, camRimDir.xz) + 1.0);         // asm 586-587
        float rimShadow = min(s.ao, min(camRimFactor, shadowTexY));                // asm 588-589
        float ndotCamRimDir = saturate(dot(camRimDir, s.normalTWS));               // asm 591
        rimLightColor = rimLight * rimShadow * ndotCamRimDir * lerp(0.25, s.diffuseColor, _RimFresnelMix);  // asm 592-596
    }

    // ---- gEnv(asm 597-631) ----
    float ndotlXZ = dot(lightXZ, s.normalTWS.xz);                                  // asm 597
    float ndotDominant = gi.dominantOn * dot(gi.dominantSHDir, s.normalTWS);       // asm 598-599
    float gEnvRadiance = saturate(lerp(ndotDominant, 0.5 - (ndotlXZ * 0.5 - 1.0) * ndotlXZ, curSceneShadow));  // asm 600-603
    float reverseRimControl = smoothstep(0.0, 1.0, saturate(reverseNdotV.y * 5.0));  // asm 604-607
    float backControl = (1.0 - _BackLightControl) * lerp(1.0, saturate(-camDotLXZ), curSceneShadow);  // asm 608-610
    float lowDiffIntensityFactor = smoothstep(0.0, 1.0, saturate((ClothLuminance(s.diffuseColor) - 0.1) * -16.6667));  // asm 611-615
    float3 normOriginSHColor = gi.originSHColor / max(max(gi.originSHColor.r, max(gi.originSHColor.g, gi.originSHColor.b)) * 0.5, 1.0);  // asm 617-622
    float3 gEnvColor = lerp(normOriginSHColor, lightColor, curSceneShadow);        // asm 623-624
    float3 gEnvColorR = gEnvColor * gEnvRadiance * backControl * reverseRimControl
        * min(s.ao, shadowTexY) * lerp(1.0, lowDiffIntensityFactor, curSceneShadow);  // asm 626-630
    // 注:asm 625 是 max(diffuseColor, 0.15) 下限而非注释的 *0.15(以指令为准)
    float3 gEnvDiffuseAndRim = max(s.diffuseColor, 0.15) * gEnvColorR + rimLightColor;  // asm 631

    // ---- IBL(asm 632-680) ----
    float roughnessIBL = lerp(s.roughness, s.wetRoughness, s.wetFactor);            // asm 632-633
    float2 brdfApprox = SpecularGGXReflectanceApproxCloth(curSpecularColor, roughnessIBL, ndotv);  // asm 634-661
    // 注:asm 662-667 是 reflectionApprox*(1 + F*(1-(A+B))/(A+B)),reflectionApprox = F*A + B(以指令为准)
    float approxSum = brdfApprox.x + brdfApprox.y;
    float3 reflectionApprox = curSpecularColor * brdfApprox.x + brdfApprox.y;
    float3 iblSpcBrdfApprox = reflectionApprox * (1.0 + curSpecularColor * (1.0 - approxSum) / approxSum);
    float3 reflectV = reflect(-viewDirWS, s.normalTWS);                            // asm 668-670
    float mip = 6.0 - (1.0 - 1.2 * log2(max(roughnessIBL, 0.001)));                // asm 671-674
    float3 envCube = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectV, mip).rgb;  // asm 675
    float3 envSpecular = iblSpcBrdfApprox * envCube * mulIntensity.z * _EnvIntensity;  // asm 676-678
    float3 mainlightResultColor = envSpecular * gi.shColor + gEnvDiffuseAndRim + mainLightResult;  // asm 679-680

    // ---- 共享状态(Step 7 附加光使用) ----
    st.resultDiffuse = resultDiffuse;
    st.styleSpecularColor = styleSpecularColor;
    st.curSpecularColor = curSpecularColor;
    st.diffuseColor = s.diffuseColor;
    st.shadowDiffuseColor = s.shadowDiffuseColor;
    st.diffuseColorMinusHalf = s.diffuseColor - 0.5;      // asm 735
    st.curSceneShadow = curSceneShadow;
    st.roughnessSqr = s.roughnessSqr;
    st.ndotv = ndotv;
    st.metallic = s.metallic;
    st.baseAlphaLerp = baseAlphaLerp;
    st.ndotDominant = ndotDominant;
    st.reverseNdotVx = 1.0 - abs(dot(viewDirWS, s.normalTWS));   // asm 575(r22.x)
    st.lightColor = lightColor;
    st.camVector = camVector;
    st.viewDirWS = viewDirWS;
    st.objectDir = objectDir;

    return mainlightResultColor;
}

// ============================================================================
// Step 7:附加光源循环(asm 681-1140)
// 索引系统替换:原两级位掩码 tile 索引删除,用 URP LIGHT_LOOP_BEGIN/END + GetAdditionalLight
// ============================================================================

// 切线半八面体解码(asm 807-817):packed.x = X(带符号), packed.y = P = a+b
// 精确互逆的 C# 编码(ClothStylizedLight.GetData,由本解码逆推):
//   L1 = |tx|+|ty|+|tz|; X = sign(ty)*(1 + (tx-tz)/L1)/2; P = (tx+tz)/L1
float3 DecodeClothTangent(float2 packed)
{
    float pp = packed.y * 0.5 + 0.5;                 // asm 807
    float a = pp - abs(packed.x);                    // asm 808
    float b = packed.y - a;                          // asm 809
    float y = (packed.x >= 0.0) ? max(1.0 - abs(a) - abs(b), 0.0) : -max(1.0 - abs(a) - abs(b), 0.0);  // asm 810-814
    return normalize(float3(b, y, a));               // asm 815-817
}

void ApplyAdditionalLights(ClothVaryings input, ClothSurfaceData s, ClothLightingState st, inout float3 mainlightResultColor)
{
#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(pixelLightCount)
        // URP 每物体光索引 -> _AdditionalLights* UBO 槽位(GetAdditionalLight 内部同样映射)
        uint slotIndex = GetPerObjectLightIndex(lightIndex);
        Light light = GetAdditionalLight(lightIndex, input.positionWS);
        ClothStylizedLightData lp = _StylizedLightParamsBuffer[slotIndex];

        // 跳过规则:类型 >= 2 对角色不起作用(原 cb3 注释 "w<2 对角色起作用")
        if (lp.colorAndType.w >= 2.0)
            continue;
        float lightMask = light.distanceAttenuation;   // URP 距离+聚光角度衰减(asm GetLocalLightAttenuation 删除)
        if (lightMask <= 0.0)                          // asm 888: if (LightMask > 0)
            continue;

        bool isSpot = lp.colorAndType.w >= 1.0;
        // 注:asm 823 的固定方向只对点光(type&1==0)生效,计划文字写 type==1 有误,以指令为准
        bool fixedDir = !isSpot && lp.modeParams0.w == 4.0 && lp.modeParams1.z > 0.5;
        float3 lightToPos = lp.positionAndInvRadius.xyz - input.positionWS;   // 指向光源(asm 820)
        float3 auxLightDir = fixedDir
            ? -lp.tangentWS.xyz * dot(lightToPos, -lp.tangentWS.xyz)          // asm 821-825
            : lightToPos;
        float3 curLightDir = normalize(auxLightDir);                          // asm 826-828

        // 胶囊光(asm 828-858,UE4 方程 16 胶囊辐照度;以 lightIrradiance 替换 distanceAttenuation)
        bool isTube = !isSpot && lp.tangentAndCapsule.w > 0.0;
        if (isTube)
        {
            float3 tangent = DecodeClothTangent(lp.tangentAndCapsule.xy);
            float3 shift1 = auxLightDir - 0.5 * tangent * lp.tangentAndCapsule.w;  // asm 832-834
            float3 shift2 = auxLightDir + 0.5 * tangent * lp.tangentAndCapsule.w;
            float len1 = length(shift1);
            float len2 = length(shift2);
            float dot12 = dot(shift1, shift2);
            // 正交基(asm 842-851,逐 swizzle 照抄)
            float3 biAuxRaw = float3(
                tangent.z * curLightDir.y - curLightDir.x * tangent.x,
                tangent.z * curLightDir.y - curLightDir.x * tangent.y,
                tangent.x * curLightDir.z - curLightDir.x * tangent.z);
            float3 biAuxDir = normalize(biAuxRaw);
            float3 orthoRaw = float3(
                biAuxDir.z * tangent.y - tangent.x * biAuxDir.x,
                biAuxDir.z * tangent.y - tangent.y * biAuxDir.y,
                biAuxDir.x * tangent.z - tangent.z * biAuxDir.z);
            float3 orthoDir = normalize(orthoRaw);
            float dot1 = dot(orthoDir, shift1) / len1;                          // asm 852-855
            float dot2 = dot(orthoDir, shift2) / len2;
            float lightIrradiance = saturate((dot1 + dot2) * 0.5) / ((len1 * len2 + dot12) * 0.5 + 1.0);  // asm 856-858
            lightMask = lightIrradiance;
            curLightDir = orthoDir;                                             // asm 859
        }

        float shadowFactor = light.shadowAttenuation;   // URP 附加光阴影(原图集采样/objectDir 回退删除)
        float ndotRL = dot(s.normalTWS, curLightDir);   // asm 1051: dot(normalTWS, representLightDir)
        float renderMode = lp.modeParams0.w;

        // ---- mode 4:直接 ndotl 混合(asm 890-905) ----
        if (renderMode == 4.0)
        {
            float lightRadian = smoothstep(0.0, 1.0, saturate(dot(s.normalWS, curLightDir) + 0.5));  // asm 891-895(用翻转 normalWS)
            lightRadian = lp.modeParams1.x * lerp(1.0, lightRadian, lp.modeParams1.w);              // asm 896-898
            mainlightResultColor = lerp(mainlightResultColor, light.color, lightMask * lightRadian); // asm 899-901
            continue;
        }

        // ---- mode 0-3 ----
        float3 addLightColor = light.color;
        float3 Diif = 0;
        float3 shadowDiif = 0;
        float nRadia;

        if (renderMode == 0.0)
        {
            // 无阴影 + ramp 色 + 普通高光(asm 908-926)
            float3 maskedColor = lightMask * light.color;
            float lColorMax = max(maskedColor.r, max(maskedColor.g, maskedColor.b));   // asm 910-911
            float lColorMaxS = max(1.0, lColorMax * (0.5 + 0.25 * st.curSceneShadow)); // asm 734, 912-914
            float lColorMaxNorm = lerp(1.0, 1.0 / lColorMaxS, lp.modeParams1.y);       // asm 915-916
            float nRadiaWrap = lerp(0.25 * lp.modeParams1.x, 1.0, saturate(ndotRL + 0.5));  // asm 918-922
            addLightColor = light.color * lColorMaxNorm * nRadiaWrap;                  // asm 917, 923
            Diif = st.resultDiffuse;                                                   // asm 924-925
            shadowDiif = st.resultDiffuse;
            shadowFactor = 1.0;                                                        // asm 926(无阴影)
        }

        if (renderMode == 1.0)
        {
            // 简单 wrapped(asm 1052-1057)
            nRadia = shadowFactor * saturate(max(-1.0, lp.modeParams1.x + ndotRL));    // asm 1053-1055(含 shadowFactor)
            shadowDiif = s.shadowDiffuseColor * lp.modeParams1.y;                      // asm 1056
            Diif = s.diffuseColor;                                                     // asm 1057
        }
        else
        {
            nRadia = saturate(ndotRL);                                                 // asm 1058-1059
        }

        if (renderMode == 3.0)
        {
            // 背光(asm 1061-1082)
            float3 crossLDir = float3(                                                // asm 1062-1063(逐 swizzle 照抄)
                st.camVector.z * curLightDir.x - curLightDir.z * st.camVector.x,
                st.camVector.x * curLightDir.y - curLightDir.x * st.camVector.y,
                st.camVector.y * curLightDir.z - curLightDir.y * st.camVector.z);
            float3 orthoLDir = normalize(float3(                                       // asm 1064-1068
                st.camVector.y * crossLDir.y - crossLDir.x * st.camVector.z,
                st.camVector.z * crossLDir.z - crossLDir.y * st.camVector.x,
                st.camVector.x * crossLDir.x - crossLDir.z * st.camVector.y));
            nRadia = saturate(dot(s.normalTWS, -orthoLDir));                           // asm 1069
            float r0m = 0.8 - lp.modeParams1.x * 0.6;                                  // asm 1070
            float r1m = 0.9 - lp.modeParams1.x * 0.4;
            float rNdotVFactor = smoothstep(0.0, 1.0, saturate((st.reverseNdotVx - r0m) / (r1m - r0m)));  // asm 1071-1077
            lightMask *= shadowFactor * rNdotVFactor;                                  // asm 1078-1079
            Diif = (s.diffuseColor - 0.5) * lp.modeParams1.y + 0.5;                    // asm 1080
            shadowDiif = 0;                                                            // asm 1081
        }

        // ---- 高光(asm 1084-1122):mode 2 特化,mode 0/1 同路径(isGlossOrMetal=1, mRS=roughnessSqr) ----
        float3 specularTerm = 0;
        if (renderMode != 3.0)
        {
            float isGlossOrMetal;
            float mRS;
            if (renderMode == 2.0)
            {
                float rRough = smoothstep(0.0, 1.0, saturate((s.roughness - (lp.modeParams1.x + 0.05)) * -10.0));  // asm 1086-1090
                float metalLink = lerp(1.0, (s.metallic > 0.5) ? 1.0 : 0.0, lp.modeParams1.z);                    // asm 1091-1092
                isGlossOrMetal = metalLink * rRough;                                                             // asm 1093
                mRS = lp.modeParams1.y;                                                                            // asm 1094
            }
            else
            {
                isGlossOrMetal = 1.0;                                                                             // asm 1095
                mRS = 0.0;
            }
            float mRoughnessSqr = lerp(st.roughnessSqr, 0.01, mRS);                                                // asm 1096
            float3 halfRepDir = normalize(st.viewDirWS + curLightDir);                                            // asm 1097-1101
            float noh = dot(s.normalTWS, halfRepDir);                                                             // asm 1102
            float d = ClothD_GGX(mRoughnessSqr * mRoughnessSqr, noh);                                             // asm 1103-1109(mRS² 作 roughnessSqrSqr)
            float ggx = d / (st.ndotv * 2.0 + mRoughnessSqr + 0.0001);                                           // asm 1110-1113
            float ggxClamped = clamp(ggx * 0.5 - 0.0001, 0.0, 100.0);                                            // asm 1114-1116
            specularTerm = isGlossOrMetal * st.styleSpecularColor * ggxClamped * lp.specularParams.z;            // asm 1117-1119
        }

        // ---- 合成(asm 1123-1130) ----
        float3 diffuseTerm = lerp(shadowDiif, Diif, nRadia) * addLightColor * lightMask;
        float3 specTerm = specularTerm * addLightColor * lightMask * nRadia;
        mainlightResultColor += diffuseTerm * st.baseAlphaLerp + specTerm;
    LIGHT_LOOP_END
#endif
}

#endif // NPRCLOTH_CLOTH_LIGHTING_INCLUDED
