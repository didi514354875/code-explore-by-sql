// NPRCharacter/FaceLighting.hlsl
// 脸部材质解码(asm PS 0-338)+ 主光管线(asm 339-645)+ 附加光源循环(asm 646-1138)+ 输出(asm 1139-1346)。
// face.shader asm 无注释,槽位语义按使用处推断;与计划公式冲突处一律以 asm 指令为准。
// 与 skin 的差异(face 以自身 asm 为准):
//   - 无 normalMap:normalTWS = 翻转几何法线;normalWS 不翻转(skin 翻转)
//   - camVectorOS(世界→对象旋转,asm 37-39)驱动 rimTint 的 camFactor 与 SDF 修正
//   - 主光 ndotlt 经 lightPorj + SDF 法线扭曲修正(asm 376-439)后采 ramp
//   - 高光用湿润法线 wetNormal(asm 521-522);wet IBL 仅湿润分支(asm 538-593)
//   - rim 含 camZFactor 与 faceControl.w 修正(asm 603-645)
//   - 附加光 mode 0 的 maxComp 缩放用 curSceneShadow(asm 700-701);mode 1 含 wet/sdf 平滑(asm 1028-1043)
#ifndef NPRCHARACTER_FACE_LIGHTING_INCLUDED
#define NPRCHARACTER_FACE_LIGHTING_INCLUDED

#include "NPRCharacterInput.hlsl"
#include "NPRCharacterFog.hlsl"
#include "FaceRain.hlsl"

// ============================================================================
// 材质解码(asm PS 0-338)
// ============================================================================
CharacterSurfaceData GetFaceSurfaceData(CharacterVaryings input, float isFrontFace)
{
    CharacterSurfaceData s = (CharacterSurfaceData)0;
    s.wetFactor = 0.0;
    s.wetRoughness = 1.0 - _Smoothness;
    s.wetNormal = 0;

    // asm 0-1: 基础色(采样 swizzle wxyz:r0.x = tex.a,asm 1 只染色 yzw)
    float4 baseTex = SAMPLE_TEXTURE2D_BIAS(_BaseMap, sampler_LinearRepeat, input.uv, _MipBias);
    s.baseColor = baseTex.rgb * _BaseColor.rgb;
    s.baseAlpha = baseTex.a;
    // asm 2-18: 颜色分级 LUT
    s.gradBaseColor = SampleCharacterColorGradeLUT(CharacterLinearToSRGB(s.baseColor));

    // asm 19: faceControl
    s.faceControl = SAMPLE_TEXTURE2D_BIAS(_FaceControlTex, sampler_LinearRepeat, input.uv, _MipBias);

    // asm 21-28: objectDir / 22-24: normalWS 归一化 / 29-32: viewDirWS
    s.objectDir = normalize(input.positionWS.xz - unity_ObjectToWorld._14_24_34.xz);
    s.normalWS = normalize(input.normalWS);
    s.viewDirWS = normalize(input.viewDirWS);

    // asm 33-35: 背面翻转(normalTWS = faceFlip * normalWS;face 的 normalWS 不翻转,与 skin 不同)
    float faceFlip = isFrontFace > 0.0 ? 1.0 : 2.0 * _DoubleSidedFlip - 1.0;
    s.normalTWS = s.normalWS * faceFlip;

    // asm 37-45: camVectorOS(世界→对象空间旋转,objToWorld 行点积 = mul 行向量语义)+ 归一化 z
    float3 camVector = UNITY_MATRIX_V._13_23_33;
    float3 camVectorOS = mul(camVector, (float3x3)unity_ObjectToWorld);
    s.faceCamZ = normalize(camVectorOS).z;   // r4.w(asm 45)

    // asm 49-57: NxzDir = normalize(lerp(objectDir, normalize(normalTWS.xz), faceControl.y))
    s.NxzDir = normalize(lerp(s.objectDir, normalize(s.normalTWS.xz), s.faceControl.y));

    // asm 232-244: rimTint(face 特有:camFactor 与 faceControl.x 参与)
    //   camFactor = lerp(saturate(camZ*0.5+0.5), 1, fc.y);rimTintFactor = fc.x * camFactor * saturate(_RimTintStrength * (1-ndotvTWS'))
    float ndotv = dot(s.normalTWS, s.viewDirWS);   // asm 237(dp3_sat,原始值仅作参考)
    s.ndotv = ndotv;
    s.ndotvTWS = saturate(ndotv);
    float camFactor = lerp(saturate(s.faceCamZ * 0.5 + 0.5), 1.0, s.faceControl.y);   // asm 232-235
    float rimTintFactor = s.faceControl.x * camFactor * saturate(_RimTintStrength * (1.0 - (s.ndotvTWS * 0.85 + 0.15)));  // asm 236-241
    float3 rimTintBaseColor = s.baseColor * lerp(1.0, _RimTintColor.xyz, rimTintFactor);   // asm 242-244

    // asm 245: specularStrength 基 = faceControl.y * _SpecularStrength
    float specularBase = s.faceControl.y * _SpecularStrength;

    // asm 246-259: 雨区(公式与 skin 相同)
    float2 xyControl = lerp(_RainAreaCenter.xy, _RainAreaControl.yw, _RainAreaControl.x);   // asm 246-248
    float distanceFactor = lerp(_RainAreaCenter.z, 1.0, _RainAreaControl.x);                // asm 249-250
    float heightFactor = smoothstep(0.0, 1.0, saturate((xyControl.y - input.positionWS.y + 0.2) * 2.8571));  // 251-256
    float rainOn = heightFactor * distanceFactor + xyControl.x;                             // 258
    float dotD = max(xyControl.x, distanceFactor * heightFactor);                           // 257, 275

    // asm 260-330: 雨湿润(修改 baseAlpha/specularStrength/wetRoughness/wetNormal)
    GetFaceRain(input, faceFlip, specularBase, dotD, rainOn, s);

    // asm 331-338: 派生颜色(粗糙度源为 wetRoughness)
    float dieletric = 0.96 - 0.96 * _Metallic;
    s.metallic = _Metallic;
    s.roughness = s.wetRoughness;
    s.diffuseColor = dieletric * rimTintBaseColor;                     // asm 332
    s.specularColor = lerp(s.specularStrength * 0.04, rimTintBaseColor, _Metallic);  // asm 333-335
    s.shadowDiffuseColor = dieletric * s.gradBaseColor;                // asm 336
    s.roughnessSqr = max(s.roughness * s.roughness, 0.0078);           // asm 337-338

    return s;
}

// ============================================================================
// 主光漫反射 ramp 管线 + 高光 + wet IBL + rim(asm 339-645)
// ============================================================================
float3 FaceLighting(CharacterVaryings input, CharacterSurfaceData s, CharacterIndirectLight gi, out CharacterLightingState st)
{
    // ---- 主光(asm 339-350) ----
    Light mainLight = GetMainLight();
    float3 lightDir = normalize(lerp(mainLight.direction, _MainLightDirOverride.xyz, _CharacterLightBlend));  // asm 339-340
    float3 lightCol = lerp(mainLight.color, _MainLightColorOverride.rgb, _LightColorOverrideBlend);            // asm 345-346
    float3 lightColor = lightCol;   // 原 *lerp(cb3[3].w, 1, cb0[171].w) 强度项删除:URP color 已含强度
    float rIntensity = CharacterLuminance(lightColor);                                                          // asm 350

    float3 camVector = UNITY_MATRIX_V._13_23_33;
    float2 lightXZ = normalize(lightDir.xz);                            // asm 341-344
    float2 camXZ = normalize(camVector.xz);                             // asm 361-363
    float camDotLXZ = dot(lightXZ, camXZ);                              // asm 364

    // ---- 场景阴影(asm 351-359) ----
    float2 sceneShadow = GetCharacterSceneShadow(input.positionCS, input.positionWS);
    float curSceneShadow = sceneShadow.x;
    float shadowSelf = sceneShadow.y;

    // ---- 背光补偿与派生色(asm 360-375) ----
    float ndotlt = dot(s.normalTWS, lightDir);                          // asm 360
    float3 shadowDiffuseScaled = s.gradBaseColor * _ShadowStrength;     // asm 365(以指令为准:gradBaseColor)
    float3 _2ndShadowDiffuseColor = AdjustCharacterSaturation(shadowDiffuseScaled * 0.65, 1.2);  // asm 366-369
    float diffIntensity = CharacterLuminance(s.diffuseColor);           // asm 370
    float3 _2ndDiffuseColor = AdjustCharacterSaturation(s.diffuseColor, 1.2);   // asm 371-372
    ndotlt = ApplyCharacterBackLight(ndotlt);                           // asm 373-375

    // ---- lightPorj 与 SDF 法线扭曲(asm 376-409,face 特有) ----
    // asm 376-380:lightDir 与物体局部 X/Z 轴(未归一化轴,与 asm 一致)点积后归一化
    float2 lightPorj = normalize(float2(dot(lightDir, unity_ObjectToWorld[0].xyz), dot(lightDir, unity_ObjectToWorld[2].xyz)));
    // asm 381-386:镜像 uv(0 < lightPorj.x 时取 uv.x)
    float2 sdfUV = float2(lerp(1.0 - input.uv.x, input.uv.x, (lightPorj.x > 0.0) ? 1.0 : 0.0), input.uv.y);
    float4 sdf = SAMPLE_TEXTURE2D_LOD(_FaceSDFTex, sampler_LinearClamp, sdfUV, 0.0);   // asm 387
    // asm 388-397:gradX/gradY(镜像选择)
    float gradX = (lightPorj.x > 0.0) ? (sdf.z * 4.0 - 2.0) : (1.0 - sdf.z * 2.0);    // asm 389-392
    float2 gradN = normalize(float2(gradX, 1.0 - abs(gradX)));                        // asm 393-397
    // asm 398-403:faceNormal = normalize(objToWorld[0]*gx + objToWorld[2]*gy)
    float3 faceNormal = normalize(unity_ObjectToWorld[0].xyz * gradN.x + unity_ObjectToWorld[2].xyz * gradN.y);
    // asm 404-409:lightingNormal = normalize(lerp(faceNormal, normalTWS, faceControl.y))
    float3 lightingNormal = normalize(lerp(faceNormal, s.normalTWS, s.faceControl.y));

    // ---- sdfRoundness 与 ramp(asm 410-447) ----
    float backBias = saturate(-lightPorj.y) * saturate(-camDotLXZ) * (1.0 - _BackLightControl);  // asm 410-416
    float parabol = 0.5 - lightPorj.y * (lightPorj.y * 0.5 - 1.0);                               // asm 411-412, 417
    float sdfNdotL = lightPorj.y + backBias * (parabol - lightPorj.y);                           // asm 417-418
    float a = clamp(0.5 - sdfNdotL * 0.5, 0.001, 0.999);                                         // asm 419-422
    float b = max(2.0 * a - 1.0, 0.0);                                                           // asm 423-425
    float e = min(2.0 * a, 1.0) - b;                                                             // asm 426-428
    float g = saturate(((sdf.x + sdf.y) * 0.5 - b) / e);                                         // asm 429-431
    float gSmooth = smoothstep(0.0, 1.0, g);                                                     // asm 432-433
    float rnd = a * 0.5 * round(a * 0.5);                                                        // asm 419, 434-435
    float roundness = 2.0 * abs(-(3.0 - 2.0 * g) * gSmooth - rnd) - 1.0;                         // asm 436-437
    ndotlt = ndotlt - roundness;                                                                 // asm 438
    float ndotltFinal = roundness + s.faceControl.y * (ndotlt - roundness);                      // asm 439: lerp(roundness, ndotlt, fc.y)
    float4 rampTex = SAMPLE_TEXTURE2D_LOD(_RampTex, sampler_LinearClamp, float2(ndotltFinal * 0.5 + 0.5, 0.5), 0.0);  // asm 440-442
    float rampTexRange = max(rampTex.r, max(rampTex.g, rampTex.b)) - min(rampTex.r, min(rampTex.g, rampTex.b));  // asm 443-447

    // ---- wet 控制与 radiance(asm 448-507) ----
    // asm 448-451:faceCamFactor = smoothstep(saturate(1.5-2*camZ))(附加光 mode 1 也用)
    float faceCamFactor = smoothstep(0.0, 1.0, saturate(1.5 - 2.0 * s.faceCamZ));
    // asm 452-457:wetControl = lerp(1, lerp(1, max(fc.z*faceCamFactor, fc.y), shadowSelf), fc.y)
    float wetControlBase = max(s.faceControl.z * faceCamFactor, s.faceControl.y);   // 452-453
    float wetControl = lerp(1.0, wetControlBase, shadowSelf);                       // 454-455(r14.w = ShadowTex self)
    wetControl = lerp(1.0, wetControl, s.faceControl.y);                            // 456-457
    float AO = s.baseAlpha;                                                         // asm 324 修正后
    float rampRadiance = saturate(rampTex.w + AO * wetControl);                     // asm 458
    float3 combineShadowDiffuseColor = lerp(_2ndShadowDiffuseColor, shadowDiffuseScaled, rampRadiance);  // asm 459-460
    float rampShadowRadiance = min(rampTex.w, min(AO, wetControl));                 // asm 461-462
    float camShadowRadiance = AO * wetControl;                                      // asm 463
    float3 shCol = lerp(gi.shColor, 1.0, rampShadowRadiance * _BakedGIStrength);    // asm 464-465
    shCol *= gi.ndotSky;                                                            // asm 466-468
    float3 lightColorM = lerp(rIntensity, lightColor, rampShadowRadiance);          // asm 469-470

    float2 mulIntensity = clamp(float2(gi.ambientIntensity, gi.ambientIntensity * 0.35 + 0.65), float2(0.0, 1.25), float2(1.5, 1.75));  // asm 471-472
    float3 lightAndAmbientCol = lightColorM + shCol * mulIntensity.x * lerp(lightCol, 1.0, _LightColorOverrideBlend);  // asm 473-476
    float mulIntensity1 = lerp(min(1.5, gi.ambientIntensity * 0.35 + 0.65), mulIntensity.y, _AmbientIntensityMix);     // asm 477-480
    float3 ambientAndLightCol = lerp(shCol * mulIntensity1 * _EnvIntensity, lightAndAmbientCol * _LightRadianceScale, curSceneShadow);  // asm 481-484

    // ---- resultDiffuse(asm 485-500) ----
    float3 curDiffuseColor = lerp(combineShadowDiffuseColor, s.diffuseColor, rampShadowRadiance);  // asm 485-486
    float curDiffuseIntensity = CharacterLuminance(curDiffuseColor);                              // asm 487
    float3 rampCurDiffuseColor = lerp(1.0, rampTex.rgb, rampTexRange) * curDiffuseColor;           // asm 488-490
    float normCurDiffuseIntensity = clamp(curDiffuseIntensity / max(CharacterLuminance(rampCurDiffuseColor), 0.001), 0.0, 1.5);  // asm 491-496
    float3 diffuseInSceneShadow = lerp(shadowDiffuseScaled, _2ndDiffuseColor, camShadowRadiance);  // asm 497-498
    float3 resultDiffuse = lerp(diffuseInSceneShadow, rampCurDiffuseColor * normCurDiffuseIntensity, curSceneShadow);  // asm 499-500

    // ---- 合成 radiance(asm 501-507) ----
    float combineRadiance = lerp(camShadowRadiance, rampShadowRadiance, curSceneShadow);           // asm 501-502
    float3 ambientAndLightRadiance = ambientAndLightCol * (combineRadiance * 0.5 + 0.5) * lerp(_ShadowStrength, 1.0, combineRadiance);  // asm 503-507

    // ---- 主光高光(asm 508-537;face 用湿润法线 wetNormal) ----
    float3 shiftLightDir = lightDir * curSceneShadow + float3(camVector.x, lerp(0.5, lightDir.y, curSceneShadow), camVector.z) * 2.0;  // asm 508-512
    float3 halfDir = normalize(normalize(shiftLightDir) + s.viewDirWS);                           // asm 513-520
    float ndotvWet = saturate(dot(s.wetNormal, s.viewDirWS));                                     // asm 521(r16.x)
    float ndothWet = dot(s.wetNormal, halfDir);                                                   // asm 522
    float ggxTerm = CharacterGGXTerm(s.roughnessSqr, ndothWet, ndotvWet, 20.0);                   // asm 523-536
    float3 specularTerm = s.specularColor * ggxTerm;                                             // asm 537

    // ---- wet IBL(asm 538-593,仅 wetFactor > 0.001) ----
    float3 envSpecular = 0;
    if (s.wetFactor > 0.001)
    {
        float roughnessIBL = lerp(s.wetRoughness, 0.01, s.wetFactor);                            // asm 540-541
        float2 brdfApprox = CharacterSpecularGGXReflectanceApprox(s.specularColor, roughnessIBL, ndotvWet);  // asm 542-570
        float approxSum = brdfApprox.x + brdfApprox.y;                                            // asm 572-573
        float3 reflectionApprox = s.specularColor * brdfApprox.x + brdfApprox.y;                  // asm 571
        float3 iblSpcBrdfApprox = reflectionApprox * (1.0 + s.specularColor * (1.0 - approxSum) / approxSum);  // asm 574-576
        float3 reflectV = reflect(-s.viewDirWS, s.wetNormal);                                     // asm 577-579
        float mip = 6.0 - (1.0 - 1.2 * log2(max(roughnessIBL, 0.001)));                           // asm 580-583
        float3 envCube = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectV, mip).rgb;  // asm 584
        envSpecular = iblSpcBrdfApprox * envCube * clamp(gi.ambientIntensity, 0.5, 1.5) * _EnvIntensity * s.wetFactor;  // asm 585-590
    }

    // ---- 合成与饱和度增强(asm 594-602) ----
    float3 ambientAndLightResultCol = ambientAndLightCol * resultDiffuse + ambientAndLightRadiance * specularTerm + envSpecular;  // asm 594-595
    float3 mainLightResult = EnhanceCharacterSaturation(ambientAndLightResultCol);               // asm 596-602

    // ---- Rim(asm 603-645,face 特有:camZFactor 与 faceControl.w 修正;body 无条件执行,645 的 and 门控) ----
    float reverseNdotVx = 1.0 - abs(dot(s.viewDirWS, lightingNormal));                            // asm 610-611(r3.y,无条件计算,附加光 mode 3 用)
    float3 rimLightColor = 0;
    if (_RimColor.a > 0.01)
    {
        float3 camRimDir = normalize(cross(camVector, _RimDir.xyz));                              // asm 604-609
        float r0 = 0.8 - _RimRange * 0.6;                                                         // asm 612
        float r1 = 0.9 - _RimRange * 0.4;
        float rimFactor = smoothstep(0.0, 1.0, saturate((reverseNdotVx - r0) / (r1 - r0)));       // asm 613-619
        float camZFactor = smoothstep(0.0, 1.0, saturate((abs(s.faceCamZ) - 0.9) * 10.0));        // asm 620-624
        float camRimDot = (dot(camVector, camRimDir) < -0.01) ? 1.0 : 0.0;                         // asm 625-627
        float rimBoost = max(camZFactor, camRimDot);                                              // asm 628
        rimFactor = rimFactor * camZFactor;                                                       // asm 629
        float rimExtra = saturate(_RimRange * 10.0 - 3.0);                                        // asm 630
        rimFactor = rimFactor + rimExtra * (rimBoost * s.faceControl.w - rimFactor);              // asm 631-632
        float3 rimLight = _RimColor.rgb * _RimColor.a * rimFactor;                                // asm 633-634
        float camRimFactor = saturate(dot(s.objectDir, camRimDir.xz) + 1.0);                      // asm 635-636
        float rimShadow = min(AO, min(camRimFactor, shadowSelf));                                 // asm 637-638
        float ndotCamRimDir = saturate(dot(camRimDir, lightingNormal));                           // asm 640
        rimLightColor = rimLight * rimShadow * ndotCamRimDir * lerp(0.25, s.diffuseColor, _RimFresnelMix);  // asm 641-644
    }
    mainLightResult += rimLightColor;                                                             // asm 646

    // ---- 共享状态(附加光循环使用) ----
    st.resultDiffuse = resultDiffuse;
    st.diffuseColor = s.diffuseColor;
    st.diffuseColorMinusHalf = s.diffuseColor - 0.5;       // asm 711
    st.gradBaseColor = s.gradBaseColor;
    st.specularColor = s.specularColor;
    st.roughnessSqr = s.roughnessSqr;
    st.roughnessDelta = 0.01 - s.roughnessSqr;             // asm 713
    st.ndotvTWS = ndotvWet;                                // asm 1106 用 r16.x(湿润 ndotv)
    st.metallicFlag = (_Metallic >= 0.5) ? 1.0 : 0.0;      // asm 699
    st.mode0Scale = 0.75 - 0.25 * curSceneShadow;          // asm 700-701
    st.reverseNdotVx = reverseNdotVx;                      // asm 611
    st.camVector = camVector;
    st.viewDirWS = s.viewDirWS;
    st.faceCamFactor = faceCamFactor;                      // asm 448-451
    st.faceCamZ = s.faceCamZ;                              // asm 45
    st.invWetControl = 1.0 / (0.1 + 0.9 * s.faceControl.y);  // asm 709-710
    st.faceControlW = s.faceControl.w;                     // asm 631/1072
    st.sdfAlpha = sdf.a;                                   // asm 387/1038
    st.lightingNormal = lightingNormal;                    // asm 409/1027

    return mainLightResult;
}

// ============================================================================
// 附加光源循环(asm 646-1138)
// 索引系统替换与 skin 相同:tile 索引删除,URP LIGHT_LOOP_BEGIN/END + GetAdditionalLight;
// 阴影图集采样删除,shadowFactor = light.shadowAttenuation。
// face 与 skin 循环差异:ndotl 用 SDF 扭曲法线 lightingNormal;mode 1 含 wet/sdf 平滑;mode 3 含 faceControl 修正。
// ============================================================================
void ApplyFaceAdditionalLights(CharacterVaryings input, CharacterSurfaceData s, CharacterLightingState st, inout float3 mainlightResultColor)
{
#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(pixelLightCount)
        uint slotIndex = GetPerObjectLightIndex(lightIndex);
        Light light = GetAdditionalLight(lightIndex, input.positionWS);
        CharacterStylizedLightData lp = _StylizedLightParamsBuffer[slotIndex];

        // 跳过规则:类型 >= 2 对角色不起作用(asm 768-770)
        if (lp.colorAndType.w >= 2.0)
            continue;
        float lightMask = light.distanceAttenuation;
        if (lightMask <= 0.0)
            continue;

        bool isSpot = lp.colorAndType.w >= 1.0;
        bool isPoint = !isSpot;
        float3 lightToPos = lp.positionAndInvRadius.xyz - input.positionWS;
        float3 curLightDir = normalize(lightToPos);

        // 胶囊光(asm 777-862):与 skin 同结构(长度读 tangentAndCapsule.w,与 Cloth 端口一致)
        bool isTube = isPoint && lp.tangentAndCapsule.w > 0.0;
        if (isTube)
        {
            float3 tangent = DecodeCharacterTangent(lp.tangentAndCapsule.xy);
            float3 orthoDir;
            float lightIrradiance = GetCharacterCapsuleIrradiance(lightToPos, curLightDir, tangent, lp.tangentAndCapsule.w, orthoDir);
            lightMask = lightIrradiance;
            curLightDir = orthoDir;
        }

        float shadowFactor = light.shadowAttenuation;
        float renderMode = lp.modeParams0.w;
        float3 addLightColor = light.color;
        float3 Diif = 0;
        float3 shadowDiif = 0;
        float nRadia;

        // ---- mode 4:直接 ndotl 混合(asm 866-881;face 用 normalTWS) ----
        if (renderMode == 4.0)
        {
            float lightRadian = smoothstep(0.0, 1.0, saturate(dot(s.normalTWS, curLightDir) + 0.5));  // asm 867-871
            lightRadian = lp.modeParams1.x * lerp(1.0, lightRadian, lp.modeParams1.w);              // asm 872-874
            mainlightResultColor = lerp(mainlightResultColor, light.color, lightMask * lightRadian); // asm 875-877
            continue;
        }

        float ndotRL = dot(st.lightingNormal, curLightDir);   // asm 1027(SDF 扭曲法线)

        if (renderMode == 1.0)
        {
            // face 特有:wet 平滑 + sdf.a 回退(asm 1028-1045)
            float nRadiaBase = clamp(ndotRL + lp.modeParams1.x, -1.0, 1.0);         // asm 1029-1031
            nRadiaBase += lp.modeParams1.z * st.faceCamFactor;                      // asm 1032
            float nRadiaSmooth = smoothstep(0.0, 1.0, saturate(nRadiaBase * st.invWetControl));  // asm 1033-1036
            nRadia = shadowFactor * nRadiaSmooth;                                   // asm 1037
            float sdfFalloff = smoothstep(0.0, 1.0, saturate((st.sdfAlpha - lp.modeParams1.w) * -5.0));  // asm 1038-1042
            nRadia = max(nRadia, sdfFalloff);                                       // asm 1043
            shadowDiif = st.gradBaseColor * lp.modeParams1.y;                       // asm 1044
            Diif = st.diffuseColor;                                                 // asm 1045
        }
        else
        {
            nRadia = saturate(ndotRL);                                              // asm 1046-1047
        }

        if (renderMode == 3.0)
        {
            // 背光(asm 1049-1078):与 skin 同结构 + face 修正项
            float3 crossLDir = float3(                                               // asm 1050-1051
                st.camVector.z * curLightDir.x - curLightDir.z * st.camVector.x,
                st.camVector.x * curLightDir.y - curLightDir.x * st.camVector.y,
                st.camVector.y * curLightDir.z - curLightDir.y * st.camVector.z);
            float3 orthoLDir = normalize(float3(                                     // asm 1052-1056
                st.camVector.y * crossLDir.y - crossLDir.x * st.camVector.z,
                st.camVector.z * crossLDir.z - crossLDir.y * st.camVector.x,
                st.camVector.x * crossLDir.x - crossLDir.z * st.camVector.y));
            nRadia = saturate(dot(st.lightingNormal, -orthoLDir));                   // asm 1057
            float r0m = 0.8 - lp.modeParams1.x * 0.6;                                // asm 1058
            float r1m = 0.9 - lp.modeParams1.x * 0.4;
            float rNdotVFactor = smoothstep(0.0, 1.0, saturate((st.reverseNdotVx - r0m) / (r1m - r0m)));  // asm 1059-1065
            float camOrthoDot = (dot(st.camVector, -orthoLDir) < -0.01) ? 1.0 : 0.0; // asm 1066-1068
            float rimBoost = max(st.faceCamZ, camOrthoDot);                          // asm 1069
            float nRadia2 = st.faceCamZ * rNdotVFactor;                              // asm 1070
            nRadia2 = nRadia2 + saturate(lp.modeParams1.x * 10.0 - 3.0) * (rimBoost * st.faceControlW - nRadia2);  // asm 1071-1073
            nRadia2 = shadowFactor * nRadia2;                                        // asm 1074
            lightMask *= nRadia2;                                                    // asm 1075
            Diif = st.diffuseColorMinusHalf * lp.modeParams1.y + 0.5;                // asm 1076
            shadowDiif = 0;                                                          // asm 1077
        }

        // ---- 高光(asm 1079-1118):mode 2 特化,mode 0/1 同路径 ----
        float3 specularTerm = 0;
        if (renderMode != 3.0)
        {
            float isGlossOrMetal;
            float mRS;
            if (renderMode == 2.0)
            {
                float rRough = smoothstep(0.0, 1.0, saturate((s.wetRoughness - (lp.modeParams1.x + 0.05)) * -10.0));  // asm 1081-1086(用湿粗糙度)
                float metalLink = lerp(1.0, st.metallicFlag, lp.modeParams1.z);    // asm 1087-1088
                isGlossOrMetal = metalLink * rRough;                               // asm 1089
                mRS = lp.modeParams1.y;                                            // asm 1090
            }
            else
            {
                isGlossOrMetal = 1.0;                                              // asm 1091
                mRS = 0.0;
            }
            float mRoughnessSqr = lerp(st.roughnessSqr, 0.01, mRS);                 // asm 1092(mRS*roughnessDelta + roughnessSqr)
            float3 halfRepDir = normalize(st.viewDirWS + curLightDir);             // asm 1093-1097
            float noh = dot(s.wetNormal, halfRepDir);                              // asm 1098(用湿润法线)
            float d = CharacterD_GGX(mRoughnessSqr * mRoughnessSqr, noh);          // asm 1099-1105
            float ggx = d / (st.ndotvTWS * 2.0 + mRoughnessSqr + 0.0001);          // asm 1106-1108
            float ggxClamped = clamp(ggx * 0.5 - 0.0001, 0.0, 100.0);              // asm 1109-1112
            specularTerm = isGlossOrMetal * st.specularColor * ggxClamped * lp.specularParams.z;  // asm 1113-1115
        }

        // ---- 合成(asm 1119-1125;face 无 baseAlphaLerp,与 skin 相同) ----
        float3 diffuseTerm = lerp(shadowDiif, Diif, nRadia) * addLightColor * lightMask;  // asm 1119-1121, 1123-1124
        float3 specTerm = specularTerm * addLightColor * lightMask * nRadia;             // asm 1122-1124
        mainlightResultColor += diffuseTerm + specTerm;                                  // asm 1125
    LIGHT_LOOP_END
#endif
}

// ============================================================================
// Fragment 入口(Forward pass,asm 1139-1346)
// ============================================================================
float4 FaceFrag(CharacterVaryings input, float isFrontFace : VFACE) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    CharacterSurfaceData s = GetFaceSurfaceData(input, isFrontFace);
    CharacterIndirectLight gi = GetCharacterIndirectLight(s, input.positionWS);
    CharacterLightingState st;
    float3 color = FaceLighting(input, s, gi, st);
    ApplyFaceAdditionalLights(input, s, st, color);
    color /= _Exposure;                                  // asm 1139
    color = ApplyCharacterFog(color, input);             // asm 1140-1328(_FogEnabled 门)
    return float4(color, 1.0);                           // asm 1343-1344(alpha 恒 1)
}

// ============================================================================
// Fragment 入口(运动矢量 pass,LightMode = ClothMotionVectors)
// ============================================================================
float4 FaceFragMotionVector(CharacterVaryings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
#if defined(_MOTION_VECTOR_PASS)
    return EncodeCharacterMotionVector(input.nonJitterScreenPos, input.oldScreenPos);
#else
    return 0;
#endif
}

#endif // NPRCHARACTER_FACE_LIGHTING_INCLUDED
