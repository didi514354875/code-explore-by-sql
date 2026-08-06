// NPRCharacter/SkinLighting.hlsl
// 皮肤材质解码(asm PS 0-288)+ 主光管线(asm 289-488)+ 附加光源循环(asm 489-951)+ 输出(asm 952-1159)。
// 命名沿用 asm 注释语义;与计划公式冲突处一律以 asm 指令为准(已在代码内标注)。
// 与 cloth 端口的差异(skin 以自身 asm 为准):
//   - 无 PBR 贴图/雨贴图/spec LUT/环境立方体;AO = baseTex.a × ShadowTex.g
//   - 雨区只改 specularF/roughness 标量(asm 260-280),无 wetNormal
//   - 附加光 mode 1 的阴影色基 = gradBaseColor(asm 865,非 shadowDiffuseColor)
//   - 附加光 mode 0 的 maxComp 缩放用 dominantOn(asm 542/721,face 用 curSceneShadow)
//   - 主光高光无 baseAlphaLerp(asm 410 直接相加)
#ifndef NPRCHARACTER_SKIN_LIGHTING_INCLUDED
#define NPRCHARACTER_SKIN_LIGHTING_INCLUDED

#include "NPRCharacterInput.hlsl"
#include "NPRCharacterFog.hlsl"

// ============================================================================
// 材质解码(asm PS 0-288)
// ============================================================================
CharacterSurfaceData GetSkinSurfaceData(CharacterVaryings input, float isFrontFace)
{
    CharacterSurfaceData s = (CharacterSurfaceData)0;
    s.wetFactor = 0.0;
    s.wetRoughness = 1.0 - _Smoothness;
    s.wetNormal = 0;

    // asm 0-1: 基础色与颜色分级 LUT
    float4 baseTex = SAMPLE_TEXTURE2D_BIAS(_BaseMap, sampler_LinearRepeat, input.uv, _MipBias);
    s.baseColor = baseTex.rgb * _BaseColor.rgb;
    s.baseAlpha = baseTex.a;
    // asm 2-8: real LinearToSRGB(逐分量 saturate);asm 9-18:32×32 LUT
    s.gradBaseColor = SampleCharacterColorGradeLUT(CharacterLinearToSRGB(s.baseColor));

    // asm 19-27: 法线解码(采样 swizzle xywz;n.xy = (2*(r*a)-1, 2*g-1),n.z = sqrt(1 - sat),*_NormalScale)
    float4 ntex = SAMPLE_TEXTURE2D_BIAS(_NormalMap, sampler_LinearRepeat, input.uv, _MipBias);
    float2 nxy = float2(ntex.r * ntex.a * 2.0 - 1.0, ntex.g * 2.0 - 1.0);
    float nz = sqrt(max(1.0 - saturate(dot(nxy, nxy)), 0.0));
    nxy *= _NormalScale;

    // asm 29-36: objectDir(xz 平面物体指向,实例偏移由 unity_ObjectToWorld 承担)
    s.objectDir = normalize(input.positionWS.xz - unity_ObjectToWorld._14_24_34.xz);

    // asm 37-40: 归一化视图方向
    s.viewDirWS = normalize(input.viewDirWS);

    // asm 41-60: TBN 构造与切线空间->世界(按 1/length(normalWS) 缩放;bitangent 用原始叉积乘符号)
    float invLen = rsqrt(max(dot(input.normalWS, input.normalWS), 1e-6));
    float3 tNormal = input.normalWS * invLen;
    float3 tTangent = input.tangentWS.xyz * invLen;
    float3 tBitangent = cross(input.normalWS, input.tangentWS.xyz) * input.tangentWS.w * invLen;
    s.normalTWS = normalize(tTangent * nxy.x + tBitangent * nxy.y + tNormal * nz);
    s.normalWS = tNormal;

    // asm 61-64: 背面翻转
    float faceFlip = isFrontFace > 0.0 ? 1.0 : 2.0 * _DoubleSidedFlip - 1.0;
    s.normalTWS *= faceFlip;
    s.normalWS *= faceFlip;

    // asm 69-72: NxzDir(GI 的 ndotSky 使用)
    s.NxzDir = normalize(s.normalTWS.xz);

    // asm 252-253: ndotv
    s.ndotv = dot(s.normalTWS, s.viewDirWS);
    s.ndotvTWS = saturate(s.ndotv);

    // asm 254-259: rimTintBaseColor = baseColor * lerp(1, _RimTintColor, saturate(_RimTintStrength * (1-ndotvTWS')))
    float rimTintFactor = saturate(_RimTintStrength * (1.0 - (s.ndotvTWS * 0.85 + 0.15)));
    float3 rimTintBaseColor = s.baseColor * lerp(1.0, _RimTintColor.xyz, rimTintFactor);

    // asm 260-273: 雨区(仅区域标量,无雨贴图)
    float2 xyControl = lerp(_RainAreaCenter.xy, _RainAreaControl.yw, _RainAreaControl.x);   // asm 261-262
    float distanceFactor = lerp(_RainAreaCenter.z, 1.0, _RainAreaControl.x);                // asm 263-264
    float heightFactor = smoothstep(0.0, 1.0, saturate((xyControl.y - input.positionWS.y + 0.2) * 2.8571));  // asm 265-270
    float rainOn = heightFactor * distanceFactor + xyControl.x;                             // asm 271-272
    float dotD = max(xyControl.x, distanceFactor * heightFactor);                           // asm 271, 274

    // asm 275-280: 雨标量(以指令为准:specularF = lerp(_SpecularStrength, 1, dotD);roughness = dotD*(_Smoothness-0.5) + (1-_Smoothness))
    float specularF = (rainOn > 0.0001) ? lerp(_SpecularStrength, 1.0, dotD) : _SpecularStrength;  // asm 276, 279
    float roughness = (rainOn > 0.0001) ? (dotD * (_Smoothness - 0.5) + (1.0 - _Smoothness)) : (1.0 - _Smoothness);  // asm 277-278, 280
    s.specularStrength = specularF;
    s.roughness = roughness;

    // asm 281-288: 派生颜色
    float dieletric = 0.96 - 0.96 * _Metallic;
    s.metallic = _Metallic;
    s.diffuseColor = dieletric * rimTintBaseColor;                     // asm 282
    s.specularColor = lerp(specularF * 0.04, rimTintBaseColor, _Metallic);  // asm 283-285
    s.shadowDiffuseColor = dieletric * s.gradBaseColor;                // asm 286
    s.roughnessSqr = max(roughness * roughness, 0.0078);               // asm 287-288

    return s;
}

// ============================================================================
// 主光漫反射 ramp 管线 + 高光 + rim + gEnv(asm 289-488)
// ============================================================================
float3 SkinLighting(CharacterVaryings input, CharacterSurfaceData s, CharacterIndirectLight gi, out CharacterLightingState st)
{
    // ---- 主光(asm 289-300) ----
    Light mainLight = GetMainLight();
    float3 lightDir = normalize(lerp(mainLight.direction, _MainLightDirOverride.xyz, _CharacterLightBlend));  // asm 289-290
    float3 lightCol = lerp(mainLight.color, _MainLightColorOverride.rgb, _LightColorOverrideBlend);            // asm 295-296
    float3 lightColor = lightCol;   // 原 *lerp(cb3[3].w, 1, cb0[171].w) 强度项删除:URP color 已含强度
    float rIntensity = CharacterLuminance(lightColor);                                                         // asm 300

    // 相机与物体方向
    float3 camVector = UNITY_MATRIX_V._13_23_33;                                        // cb0[6]:相机世界前向
    float2 lightXZ = normalize(lightDir.xz);                                            // asm 291-294

    // ---- 场景阴影(asm 301-309) ----
    float2 sceneShadow = GetCharacterSceneShadow(input.positionCS, input.positionWS);
    float curSceneShadow = sceneShadow.x;
    float shadowTexY = sceneShadow.y;

    // ---- 背光补偿与 ramp(asm 310-329) ----
    float ndotlt = dot(s.normalTWS, lightDir);                                          // asm 310
    float3 shadowDiffuseScaled = s.gradBaseColor * _ShadowStrength;                     // asm 311(以指令为准:gradBaseColor 而非 shadowDiffuseColor)
    float3 _2ndShadowDiffuseColor = AdjustCharacterSaturation(shadowDiffuseScaled * 0.65, 1.2);  // asm 312-315
    float diffIntensity = CharacterLuminance(s.diffuseColor);                           // asm 316
    float3 _2ndDiffuseColor = AdjustCharacterSaturation(s.diffuseColor, 1.2);           // asm 317-318
    ndotlt = ApplyCharacterBackLight(ndotlt);                                           // asm 319-321
    float4 rampTex = SAMPLE_TEXTURE2D_LOD(_RampTex, sampler_LinearClamp, float2(ndotlt * 0.5 + 0.5, 0.5), 0.0);  // asm 322-324
    float rampTexRange = max(rampTex.r, max(rampTex.g, rampTex.b)) - min(rampTex.r, min(rampTex.g, rampTex.b));  // asm 325-329

    // ---- radiance 与漫反射合成(asm 330-372) ----
    float AO = s.baseAlpha * shadowTexY;                                                // asm 330
    float rampRadiance = saturate(rampTex.w + AO);                                      // asm 331
    float3 combineShadowDiffuseColor = lerp(_2ndShadowDiffuseColor, shadowDiffuseScaled, rampRadiance);  // asm 332-333
    float rampShadowRadiance = min(rampTex.w, min(AO, shadowTexY));                     // asm 334-335
    float3 shCol = lerp(gi.shColor, 1.0, rampShadowRadiance * _BakedGIStrength);        // asm 336-339
    shCol *= gi.ndotSky;                                                                // asm 340
    float3 lightColorM = lerp(rIntensity, lightColor, rampShadowRadiance);              // asm 341-342

    // ---- 环境与光合成(asm 343-356) ----
    float2 mulIntensity = clamp(float2(gi.ambientIntensity, gi.ambientIntensity * 0.35 + 0.65), float2(0.0, 1.25), float2(1.5, 1.75));  // asm 343-344
    float3 lightAndAmbientCol = lightColorM + shCol * mulIntensity.x * lerp(lightCol, 1.0, _LightColorOverrideBlend);  // asm 345-348
    float mulIntensity1 = lerp(min(1.5, gi.ambientIntensity * 0.35 + 0.65), mulIntensity.y, _AmbientIntensityMix);     // asm 349-352
    float3 ambientAndLightCol = lerp(shCol * mulIntensity1 * _EnvIntensity, lightAndAmbientCol * _LightRadianceScale, curSceneShadow);  // asm 353-356

    // ---- resultDiffuse(asm 357-372) ----
    float3 curDiffuseColor = lerp(combineShadowDiffuseColor, s.diffuseColor, rampShadowRadiance);  // asm 357-358
    float curDiffuseIntensity = CharacterLuminance(curDiffuseColor);                              // asm 359
    float3 rampCurDiffuseColor = lerp(1.0, rampTex.rgb, rampTexRange) * curDiffuseColor;           // asm 360-362
    float normCurDiffuseIntensity = clamp(curDiffuseIntensity / max(CharacterLuminance(rampCurDiffuseColor), 0.001), 0.0, 1.5);  // asm 363-368
    float3 diffuseInSceneShadow = lerp(shadowDiffuseScaled, _2ndDiffuseColor, AO);                // asm 369-370
    float3 resultDiffuse = lerp(diffuseInSceneShadow, rampCurDiffuseColor * normCurDiffuseIntensity, curSceneShadow);  // asm 371-372

    // ---- 合成 radiance(asm 373-379) ----
    float combineRadiance = lerp(AO, rampShadowRadiance, curSceneShadow);                         // asm 373-374
    float3 ambientAndLightRadiance = ambientAndLightCol * (combineRadiance * 0.5 + 0.5) * lerp(_ShadowStrength, 1.0, combineRadiance);  // asm 375-379

    // ---- 主光高光(asm 380-410) ----
    float3 shiftLightDir = lightDir * curSceneShadow + float3(camVector.x, lerp(0.5, lightDir.y, curSceneShadow), camVector.z) * 2.0;  // asm 380-384
    float3 halfDir = normalize(normalize(shiftLightDir) + s.viewDirWS);                           // asm 385-392
    float ndoth = dot(s.normalTWS, halfDir);                                                     // asm 393
    float ggxTerm = CharacterGGXTerm(s.roughnessSqr, ndoth, s.ndotvTWS, 20.0);                    // asm 394-407
    float3 specularTerm = s.specularColor * ggxTerm;                                             // asm 408
    float3 ambientAndLightResultCol = ambientAndLightCol * resultDiffuse + ambientAndLightRadiance * specularTerm;  // asm 409-410

    // 亮度饱和度增强(asm 411-417;lerp 系数 >1,照抄)
    float3 mainLightResult = EnhanceCharacterSaturation(ambientAndLightResultCol);

    // ---- Rim(asm 418-446) ----
    float3 rimLightColor = GetCharacterRimLight(s.normalTWS, s.ndotv, s.objectDir, AO, shadowTexY, s.diffuseColor);

    // ---- gEnv(asm 447-487) ----
    float2 camXZ = normalize(camVector.xz);                                                    // asm 447-449
    float camDotLXZ = dot(lightXZ, camXZ);                                                     // asm 450
    float ndotlXZ = dot(lightXZ, s.normalTWS.xz);                                              // asm 451
    float ndotDominant = gi.dominantOn * dot(gi.dominantSHDir, s.normalTWS);                    // asm 452-453
    float gEnvRadiance = saturate(lerp(ndotDominant, 0.5 - (ndotlXZ * 0.5 - 1.0) * ndotlXZ, curSceneShadow));  // asm 454-457
    float reverseRimControl = smoothstep(0.0, 1.0, saturate((0.4 - abs(s.ndotv)) * 5.0));      // asm 458-462
    float backControl = (1.0 - _BackLightControl) * lerp(1.0, -camDotLXZ, curSceneShadow);     // asm 463-466
    float lowDiffIntensityFactor = smoothstep(0.0, 1.0, saturate((diffIntensity - 0.1) * -16.6667));  // asm 467-472
    float3 normOriginSHColor = gi.originSHColor / max(max(gi.originSHColor.r, max(gi.originSHColor.g, gi.originSHColor.b)) * 0.5, 1.0);  // asm 473-478
    float3 gEnvColor = lerp(normOriginSHColor, lightColor, curSceneShadow);                     // asm 479-480
    float3 gEnvColorR = gEnvColor * gEnvRadiance * backControl * reverseRimControl
        * min(AO, shadowTexY) * lerp(1.0, lowDiffIntensityFactor, curSceneShadow);              // asm 482-486
    float3 gEnvDiffuseAndRim = max(s.diffuseColor, 0.15) * gEnvColorR + rimLightColor;          // asm 481, 487
    mainLightResult += gEnvDiffuseAndRim;                                                       // asm 488

    // ---- 共享状态(附加光循环使用) ----
    st.resultDiffuse = resultDiffuse;
    st.diffuseColor = s.diffuseColor;
    st.diffuseColorMinusHalf = s.diffuseColor - 0.5;       // asm 543
    st.gradBaseColor = s.gradBaseColor;
    st.specularColor = s.specularColor;
    st.roughnessSqr = s.roughnessSqr;
    st.roughnessDelta = 0.01 - s.roughnessSqr;             // asm 545
    st.ndotvTWS = s.ndotvTWS;
    st.metallicFlag = (_Metallic >= 0.5) ? 1.0 : 0.0;      // asm 541
    st.mode0Scale = 0.75 - 0.25 * gi.dominantOn;           // asm 542
    st.reverseNdotVx = 1.0 - abs(s.ndotv);                 // asm 425(r11.x)
    st.camVector = camVector;
    st.viewDirWS = s.viewDirWS;
    st.faceCamFactor = 0;
    st.faceCamZ = 0;
    st.invWetControl = 0;
    st.faceControlW = 0;
    st.sdfAlpha = 0;
    st.lightingNormal = s.normalTWS;

    return mainLightResult;
}

// ============================================================================
// 附加光源循环(asm 489-951)
// 索引系统替换:原两级位掩码 tile 索引(t0 结构化缓冲)删除,用 URP LIGHT_LOOP_BEGIN/END
// + GetAdditionalLight;阴影图集采样(asm 757-855,Tent5x5)与 objectDir 回退(853-855)删除,
// shadowFactor = light.shadowAttenuation(_ADDITIONAL_LIGHT_SHADOWS 控制)。
// asm 的 spotFade(590-595)与引擎衰减链(669-695)由 URP distanceAttenuation 承担。
// ============================================================================
void ApplySkinAdditionalLights(CharacterVaryings input, CharacterSurfaceData s, CharacterLightingState st, inout float3 mainlightResultColor)
{
#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(pixelLightCount)
        // URP 每物体光索引 -> _AdditionalLights* UBO 槽位(GetAdditionalLight 内部同样映射)
        uint slotIndex = GetPerObjectLightIndex(lightIndex);
        Light light = GetAdditionalLight(lightIndex, input.positionWS);
        CharacterStylizedLightData lp = _StylizedLightParamsBuffer[slotIndex];

        // 跳过规则:类型 >= 2 对角色不起作用(asm 601)
        if (lp.colorAndType.w >= 2.0)
            continue;
        float lightMask = light.distanceAttenuation;   // URP 距离+聚光角度衰减
        if (lightMask <= 0.0)                          // asm 697: lightMask > 0 才执行
            continue;

        bool isSpot = lp.colorAndType.w >= 1.0;
        bool isPoint = !isSpot;
        float3 lightToPos = lp.positionAndInvRadius.xyz - input.positionWS;   // 指向光源(asm 628)
        float3 curLightDir = normalize(lightToPos);                           // asm 628-636

        // 胶囊光(asm 609-695):isTube = 点光 && 胶囊长度 > 0。
        // asm 的槽位 2.z 是胶囊长度、2.w 是阴影图集打包;与 Cloth 共用 C# 缓冲,
        // 长度改读 tangentAndCapsule.w(与 Cloth 端口一致),阴影图集项删除。
        bool isTube = isPoint && lp.tangentAndCapsule.w > 0.0;
        if (isTube)
        {
            float3 tangent = DecodeCharacterTangent(lp.tangentAndCapsule.xy);   // asm 615-625
            float3 orthoDir;
            float lightIrradiance = GetCharacterCapsuleIrradiance(lightToPos, curLightDir, tangent, lp.tangentAndCapsule.w, orthoDir);  // asm 639-667
            lightMask = lightIrradiance;                                        // asm 668 + 696(URP 距离衰减替换)
            curLightDir = orthoDir;                                             // asm 668
        }

        float shadowFactor = light.shadowAttenuation;   // URP 附加光阴影(原图集采样/objectDir 回退删除)
        float renderMode = lp.modeParams0.w;
        float3 addLightColor = light.color;
        float3 Diif = 0;
        float3 shadowDiif = 0;
        float nRadia;

        // ---- mode 4:直接 ndotl 混合(asm 699-714;用翻转后 normalWS) ----
        if (renderMode == 4.0)
        {
            float lightRadian = smoothstep(0.0, 1.0, saturate(dot(s.normalWS, curLightDir) + 0.5));  // asm 700-704
            lightRadian = lp.modeParams1.x * lerp(1.0, lightRadian, lp.modeParams1.w);              // asm 705-707
            mainlightResultColor = lerp(mainlightResultColor, light.color, lightMask * lightRadian); // asm 708-710
            continue;
        }

        float ndotRL = dot(s.normalTWS, curLightDir);   // asm 860

        if (renderMode == 0.0)
        {
            // 无阴影 + ramp 色 + 普通高光(asm 717-735)
            float3 maskedColor = lightMask * light.color;                          // asm 718
            float lColorMax = max(maskedColor.r, max(maskedColor.g, maskedColor.b));   // asm 719-720
            float lColorMaxS = max(1.0, lColorMax * st.mode0Scale);                    // asm 721-722(mode0Scale = 0.75-0.25*dominantOn)
            float lColorMaxNorm = lerp(1.0, 1.0 / lColorMaxS, lp.modeParams1.y);       // asm 723-725
            // 注:skin 常数 0.5(与 cloth 端口的 0.25 不同,以 asm 727-731 为准)
            float nRadiaWrap = lerp(0.5 * lp.modeParams1.x, 1.0, saturate(ndotRL + 0.5));  // asm 727-731
            addLightColor = light.color * lColorMaxNorm * nRadiaWrap;                // asm 726, 732
            Diif = st.resultDiffuse;                                                 // asm 733
            shadowDiif = st.resultDiffuse;                                           // asm 734
            shadowFactor = 1.0;                                                      // asm 735(无阴影)
        }

        if (renderMode == 1.0)
        {
            // 简单 wrapped(asm 862-866)
            nRadia = shadowFactor * saturate(ndotRL + lp.modeParams1.x);    // asm 862-864(max_sat → 等效 saturate)
            shadowDiif = st.gradBaseColor * lp.modeParams1.y;               // asm 865(以指令为准:gradBaseColor)
            Diif = st.diffuseColor;                                         // asm 866
        }
        else
        {
            nRadia = saturate(ndotRL);                                      // asm 867-868
        }

        if (renderMode == 3.0)
        {
            // 背光(asm 870-891)
            float3 crossLDir = float3(                                       // asm 871-872(逐 swizzle 照抄)
                st.camVector.z * curLightDir.x - curLightDir.z * st.camVector.x,
                st.camVector.x * curLightDir.y - curLightDir.x * st.camVector.y,
                st.camVector.y * curLightDir.z - curLightDir.y * st.camVector.z);
            float3 orthoLDir = normalize(float3(                             // asm 873-877
                st.camVector.y * crossLDir.y - crossLDir.x * st.camVector.z,
                st.camVector.z * crossLDir.z - crossLDir.y * st.camVector.x,
                st.camVector.x * crossLDir.x - crossLDir.z * st.camVector.y));
            nRadia = saturate(dot(s.normalTWS, -orthoLDir));                 // asm 878
            float r0m = 0.8 - lp.modeParams1.x * 0.6;                        // asm 879
            float r1m = 0.9 - lp.modeParams1.x * 0.4;
            float rNdotVFactor = smoothstep(0.0, 1.0, saturate((st.reverseNdotVx - r0m) / (r1m - r0m)));  // asm 880-886
            lightMask *= shadowFactor * rNdotVFactor;                        // asm 887-888
            Diif = st.diffuseColorMinusHalf * lp.modeParams1.y + 0.5;        // asm 889(asm 543 后 r8 = diffuseColor-0.5)
            shadowDiif = 0;                                                  // asm 890
        }

        // ---- 高光(asm 892-931):mode 2 特化,mode 0/1 同路径(isGlossOrMetal=1, mRS=0) ----
        float3 specularTerm = 0;
        if (renderMode != 3.0)
        {
            float isGlossOrMetal;
            float mRS;
            if (renderMode == 2.0)
            {
                float rRough = smoothstep(0.0, 1.0, saturate((s.roughness - (lp.modeParams1.x + 0.05)) * -10.0));  // asm 894-899
                float metalLink = lerp(1.0, st.metallicFlag, lp.modeParams1.z);                    // asm 900-901
                isGlossOrMetal = metalLink * rRough;                                             // asm 902
                mRS = lp.modeParams1.y;                                                          // asm 903
            }
            else
            {
                isGlossOrMetal = 1.0;                                                            // asm 904
                mRS = 0.0;
            }
            float mRoughnessSqr = lerp(st.roughnessSqr, 0.01, mRS);                               // asm 905(mRS*roughnessDelta + roughnessSqr)
            float3 halfRepDir = normalize(st.viewDirWS + curLightDir);                           // asm 906-910
            float noh = dot(s.normalTWS, halfRepDir);                                            // asm 911
            float d = CharacterD_GGX(mRoughnessSqr * mRoughnessSqr, noh);                        // asm 912-918
            float ggx = d / (st.ndotvTWS * 2.0 + mRoughnessSqr + 0.0001);                        // asm 919-922
            float ggxClamped = clamp(ggx * 0.5 - 0.0001, 0.0, 100.0);                            // asm 923-925
            specularTerm = isGlossOrMetal * st.specularColor * ggxClamped * lp.specularParams.z; // asm 926-928
        }

        // ---- 合成(asm 932-938;skin 无 baseAlphaLerp,与 cloth 不同) ----
        float3 diffuseTerm = lerp(shadowDiif, Diif, nRadia) * addLightColor * lightMask;         // asm 932-934, 937
        float3 specTerm = specularTerm * addLightColor * lightMask * nRadia;                     // asm 935-937
        mainlightResultColor += diffuseTerm + specTerm;                                          // asm 938
    LIGHT_LOOP_END
#endif
}

// ============================================================================
// Fragment 入口(Forward pass,asm 952-1159)
// ============================================================================
float4 SkinFrag(CharacterVaryings input, float isFrontFace : VFACE) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    CharacterSurfaceData s = GetSkinSurfaceData(input, isFrontFace);
    CharacterIndirectLight gi = GetCharacterIndirectLight(s, input.positionWS);
    CharacterLightingState st;
    float3 color = SkinLighting(input, s, gi, st);
    ApplySkinAdditionalLights(input, s, st, color);
    color /= _Exposure;                                  // asm 952
    color = ApplyCharacterFog(color, input);             // asm 953-1140(_FogEnabled 门)
    return float4(color, 1.0);                           // asm 1156-1157(alpha 恒 1)
}

// ============================================================================
// Fragment 入口(运动矢量 pass,LightMode = ClothMotionVectors)
// ============================================================================
float4 SkinFragMotionVector(CharacterVaryings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
#if defined(_MOTION_VECTOR_PASS)
    return EncodeCharacterMotionVector(input.nonJitterScreenPos, input.oldScreenPos);
#else
    return 0;
#endif
}

#endif // NPRCHARACTER_SKIN_LIGHTING_INCLUDED
