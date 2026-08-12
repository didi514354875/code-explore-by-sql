// ShaolvQianxian2/ShaolvLighting.hlsl
// 像素着色器,对应原始 asm PS 0-491 逐段移植。
// 模块:材质解码+法线(0-23)/级联阴影 3x3 PCF(24-127)/主光 BRDF+卡通(128-275)/
//       附加光循环(276-457)/反射探针+贴花(458-468)/输出编码(469-491)。
// URP 内置等价:主光方向/颜色(_MainLightPosition/_MainLightColor,原 cb0[7]/cb0[8])、
// 级联矩阵(_MainLightWorldToShadow,原 cb0[1400+i*4..1403])、级联球(_CascadeShadowSplitSpheres0-3,
// 原 cb0[1420..1423]+cb0[1424])、阴影尺寸(_MainLightShadowmapSize,原 cb0[1430])、
// 阴影强度(_MainLightShadowParams.x,原 cb0[1429].x)、SH 系数(unity_SH*,原 cb1[17..23],按 asm 布局重排)、
// 反射探针(unity_SpecCube0,原 t0)。光照公式(衰减/GGX/ramp)与 URP 内置不同,逐条照抄 asm。
#ifndef SHAOLV_LIGHTING_INCLUDED
#define SHAOLV_LIGHTING_INCLUDED

#include "ShaolvVertex.hlsl"

// ============================================================================
// 3x3 PCF 阴影采样(asm 58-121 主光 / 315-377 附加光同构,逐条照抄 swizzle)
// shadowmapSize: xy = 1/贴图尺寸, zw = 贴图尺寸(_MainLightShadowmapSize / _AdditionalShadowmapSize)
// ============================================================================
float ShaolvSampleShadowPCF3x3(TEXTURE2D_SHADOW_PARAM(shadowTex, shadowSampler), float3 shadowCoord, float4 shadowmapSize)
{
    // asm 58-60: 纹素坐标与小数偏移(f ∈ [-0.5, 0.5))
    float2 texelPos = shadowCoord.xy * shadowmapSize.zw;
    float2 texelBase = floor(texelPos + 0.5);
    float2 f = texelPos - texelBase;

    // asm 61-76: 9 个 tent 权重分量
    float4 r10 = float4(f.x + 0.5, f.x + 1.0, f.y + 0.5, f.y + 1.0);
    float4 r11 = r10.xxzz * r10.xxzz;
    r10.xz = r11.yywy * 0.08;
    r11.xy = r11.xzxx * 0.5 - f;
    r11.zw = 1.0 - f;
    float4 r12 = float4(min(f, 0.0), 0.0, 0.0);        // asm 66(仅 xy 参与,zw 为 82-83 的暂存)
    r12.xy = -r12.xy * r12.xy + r11.zw;                // asm 67
    float2 r9 = max(f, 0.0);                           // asm 68
    r9 = -r9 * r9 + r10.yw;                            // asm 69
    r12.xy += 1.0;                                     // asm 70
    r9 += 1.0;                                         // asm 71
    float4 r13 = float4(r11.xy * 0.16, 0.0, 0.0);      // asm 72(仅 xy)
    r11.xy = r11.zw * 0.16;                            // asm 73
    r12.xy *= 0.16;                                    // asm 74
    float4 r14 = float4(r9 * 0.16, 0.0, 0.0);          // asm 75(仅 xy)
    r9 = r10.yw * 0.16;                                // asm 76

    // asm 77-86: 权重分组(r15/r9w 为行/列权重和)
    r13.z = r12.x;
    r13.w = r9.x;
    r11.z = r14.x;
    r11.w = r10.x;
    float4 r15 = r11.zwxz + r13.zwxz;
    r12.z = r13.y;
    r12.w = r9.y;
    r14.z = r11.y;
    r14.w = r10.z;
    float3 r9w = float3(r12.z + r14.z, r12.y + r14.y, r12.w + r14.w);

    // asm 87-92: 归一化权重 + 纹素偏移常数
    r10.xyz = float3(r11.x, r11.z, r11.w) / float3(r15.z, r15.w, r15.y) + float3(-2.5, -0.5, 1.5);
    r11.xyz = float3(r14.z, r14.y, r14.w) / r9w + float3(-2.5, -0.5, 1.5);
    r10.xyz = r10.yxz * shadowmapSize.x;
    r11.xyz = r11.xyz * shadowmapSize.y;

    // asm 93-99: 9 个采样坐标 = 中心纹素 * texelSize + 偏移 * texelSize
    float2 baseUV = texelBase * shadowmapSize.xy;
    float4 r12uv = baseUV.xyxy + float4(r10.y, r10.w, r10.x, r10.w);
    float2 r13uv = baseUV + r10.zw;
    r11.w = r10.y;
    r10.yw = r11.yz;
    float4 r14uv = baseUV.xyxy + float4(r10.x, r10.y, r10.z, r10.y);
    float4 r11uv = baseUV.xyxy + float4(r11.w, r11.y, r11.w, r11.z);
    float4 r10uv = baseUV.xyxy + float4(r10.x, r10.w, r10.z, r10.w);

    // asm 101-103: 采样权重(r9.z 恒为 shadowCoord.z,未参与)
    float4 r16 = float4(r9w.x * r15.z, r9w.x * r15.w, r9w.x * r15.y, r9w.y * r15.z);
    float4 r17 = float4(r9w.y * r15.x, r9w.y * r15.y, r9w.z * r15.z, r9w.z * r15.w);
    float wLast = r9w.z * r15.y;

    // asm 104-121: 9 次比较采样加权求和(参考深度 shadowCoord.z)
    float sum = r16.x * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r12uv.xy, shadowCoord.z))
              + r16.y * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r12uv.zw, shadowCoord.z));
    sum += r16.z * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r13uv.xy, shadowCoord.z));
    sum += r16.w * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r11uv.xy, shadowCoord.z));
    sum += r17.x * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r14uv.xy, shadowCoord.z));
    sum += r17.y * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r14uv.zw, shadowCoord.z));
    sum += r17.z * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r11uv.zw, shadowCoord.z));
    sum += r17.w * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r10uv.xy, shadowCoord.z));
    sum += wLast * SAMPLE_TEXTURE2D_SHADOW(shadowTex, shadowSampler, float3(r10uv.zw, shadowCoord.z));
    return sum;
}

// 主光级联阴影(asm 24-127):级联选择(距离球)+ 级联偏移 + 3x3 PCF
float ShaolvMainLightShadow(float3 positionWS, float3 geometricNormalWS, bool cascadeShadowOn, float3 lightDir)
{
    // asm 28-29: 阴影位置 = 世界位置 + 沿主光方向偏移(开关 cb2[27].x)
    float3 shadowPos = positionWS + (cascadeShadowOn ? _ShadowOffset * lightDir : 0.0);

#if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
    // asm 30-44: 级联球选择(URP _CascadeShadowSplitSpheres0-3 = 原 cb0[1420..1423]+cb0[1424])
    float4 distSq = float4(
        dot(shadowPos - _CascadeShadowSplitSpheres0.xyz, shadowPos - _CascadeShadowSplitSpheres0.xyz),
        dot(shadowPos - _CascadeShadowSplitSpheres1.xyz, shadowPos - _CascadeShadowSplitSpheres1.xyz),
        dot(shadowPos - _CascadeShadowSplitSpheres2.xyz, shadowPos - _CascadeShadowSplitSpheres2.xyz),
        dot(shadowPos - _CascadeShadowSplitSpheres3.xyz, shadowPos - _CascadeShadowSplitSpheres3.xyz));
    float4 inside = distSq < float4(_CascadeShadowSplitSpheres0.w, _CascadeShadowSplitSpheres1.w,
                                    _CascadeShadowSplitSpheres2.w, _CascadeShadowSplitSpheres3.w);
    // asm 40-42: 第一个命中级联之后的后续级联截断(b_i && !b_{i-1})
    float4 sel = float4(inside.x, inside.y && !inside.x, inside.z && !inside.y, inside.w && !inside.z);
    float cascadeIndex = 4.0 - dot(sel, float4(4.0, 3.0, 2.0, 1.0));   // asm 43-44
    uint cascade = min((uint)cascadeIndex, 3u);                        // asm 45 ftou(越界钳制,bias 槽位)

    // asm 46-50: 级联偏移(depthBias 沿光方向;normalBias 随 1-saturate(NdotL) 缩放)
    float depthBias = _CascadeDepthBias[cascade];
    float normalBias = _CascadeNormalBias[cascade] * -(1.0 - saturate(dot(lightDir, geometricNormalWS)));
    shadowPos = shadowPos - lightDir * depthBias + geometricNormalWS * normalBias;   // asm 51-52

    // asm 53-57: 级联矩阵(URP _MainLightWorldToShadow[4] 为 no-op 矩阵,越界像素由 z range check 兜底)
    float4 shadowCoord = mul(_MainLightWorldToShadow[min(cascade, 4u)], float4(shadowPos, 1.0));

    // asm 58-121: 3x3 PCF
    float shadow = ShaolvSampleShadowPCF3x3(TEXTURE2D_SHADOW_ARGS(_MainLightShadowmapTexture, sampler_LinearClampCompare),
                                            shadowCoord, _MainLightShadowmapSize);
    // asm 122-123: 阴影强度 lerp(1, shadow, cb0[1429].x)
    shadow = lerp(1.0, shadow, _MainLightShadowParams.x);
    // asm 124-127: 采样坐标越界 → 1
    shadow = (shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0) ? 1.0 : shadow;
    return shadow;
#else
    return 1.0;
#endif
}

// 附加光阴影(asm 309-395):矩阵 + 透视除法 + 3x3 PCF;无阴影光返回 1
float ShaolvAdditionalLightShadow(float3 shadowPosWS, uint lightIndex)
{
#if defined(_ADDITIONAL_LIGHT_SHADOWS)
    half4 shadowParams = GetAdditionalLightShadowParams(lightIndex);
    int sliceIndex = (int)shadowParams.w;
    if (sliceIndex < 0)
        return 1.0;
    // asm 310-314: 世界->阴影(附加光矩阵含透视,需 w 除法;原 cb0[li*4+1431..1434])
    float4 shadowCoord = mul(_AdditionalLightsWorldToShadow[sliceIndex], float4(shadowPosWS, 1.0));
    shadowCoord.xyz /= shadowCoord.w;
    // asm 315-377: 3x3 PCF(尺寸用 _AdditionalShadowmapSize,原 cb0[2715])
    float shadow = ShaolvSampleShadowPCF3x3(TEXTURE2D_SHADOW_ARGS(_AdditionalLightsShadowmapTexture, sampler_LinearClampCompare),
                                            shadowCoord, _AdditionalShadowmapSize);
    // asm 379-380: 阴影强度 lerp(原 cb0[li+2455].x)
    shadow = lerp(1.0, shadow, shadowParams.x);
    // asm 381-383 + 394-395: 越界 → 1
    shadow = (shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0) ? 1.0 : shadow;
    return min(shadow, 1.0);
#else
    return 1.0;
#endif
}

// ============================================================================
// 输出结构:o0 颜色 / o1 rg=八面体法线 b=材质id a=窗户遮罩 / o2 xy=屏幕空间偏移 zw=0
// ============================================================================
struct ShaolvFragmentOutput
{
    float4 color        : SV_Target0;
    float4 normalMask   : SV_Target1;
    float4 screenOffset : SV_Target2;
};

ShaolvFragmentOutput ShaolvFrag(ShaolvVaryings input, bool isFrontFace : SV_IsFrontFace)
{
    ShaolvFragmentOutput output = (ShaolvFragmentOutput)0;

    // asm 0: 背面法线翻转(含 w 分量 = positionWS.x,后续 25 行重建位置用)
    float4 flippedNormal = isFrontFace > 0.0 ? input.worldNormal : -input.worldNormal;
    float3 geometricNormalWS = flippedNormal.xyz;

    // asm 1-5: uv 变换(cb2[0])与漫反射/参数贴图采样
    float2 uv = input.uvAndUv1.xy * _BaseMap_ST.xy + _BaseMap_ST.zw;
    float4 diffuseTex = SAMPLE_TEXTURE2D(_DiffuseTex, sampler_LinearRepeat, uv);
    float3 baseColor = diffuseTex.rgb * _BaseColor.rgb;         // asm 3
    float4 pbr = SAMPLE_TEXTURE2D(_PBRParamTex, sampler_LinearRepeat, uv);
    float roughness = pbr.r;
    float metallic = pbr.g;
    float occlusion = pbr.b;
    float decal = pbr.a;
    float3 baseColorDecal = baseColor * _DecalStrength;         // asm 5

    // asm 6-13: 法线贴图解码(n.xy = (2*(x*a)-1, 2*(1-y)-1), n.z = sqrt(1-min(dot,1)))
    float4 normalTex = SAMPLE_TEXTURE2D(_NormalTex, sampler_LinearRepeat, uv);
    float2 nTS = float2(normalTex.x * normalTex.w, 1.0 - normalTex.y) * 2.0 - 1.0;
    float nz = sqrt(1.0 - min(dot(nTS, nTS), 1.0));

    // asm 14-19: TBN 到世界(切线/副切线/几何法线,归一化)
    float3 surfaceNormal = normalize(input.worldTangent.xyz * nTS.x + input.worldBinormal.xyz * nTS.y + geometricNormalWS * nz);

    // asm 20-23: 视图方向归一化
    float3 viewDirWS = normalize(input.worldViewDir.xyz);

    // asm 24: 功能开关 cb2[27](x=级联阴影, y=卡通, w=SH 细节去除)
    bool cascadeShadowOn = _CascadeShadowOn > 0.0;
    bool toonOn = _ToonOn > 0.0;
    bool shDetailRemoval = _SHDetailRemoval > 0.0;

    // asm 25-27: 世界位置由 w 分量重建(背面时 x 已翻转,照抄)
    float3 positionWS = float3(flippedNormal.w, input.worldTangent.w, input.worldBinormal.w);

    // ---- 主光(URP _MainLightPosition.xyz / _MainLightColor.rgb = 原 cb0[7]/cb0[8]) ----
    float3 lightDir = _MainLightPosition.xyz;
    float3 lightColor = _MainLightColor.rgb;

    // asm 24-127: 主光级联阴影
    float mainShadow = ShaolvMainLightShadow(positionWS, geometricNormalWS, cascadeShadowOn, lightDir);

    // asm 128-133: ndotl / halfDir / ndoth / vdoth
    float ndotl = max(dot(surfaceNormal, lightDir), 0.0);

    // 临时调试:法线y/lightDir-y 符号(验证后删除)
    if (_WindowMaskStrength < -0.5)
    {
        output.color = float4(surfaceNormal.y > 0.0 ? 1.0 : 0.0, lightDir.y > 0.0 ? 1.0 : 0.0, ndotl > 0.1 ? 1.0 : 0.0, 1.0);
        return output;
    }
    float3 halfDir = normalize(viewDirWS + lightDir);
    float ndoth = max(dot(surfaceNormal, halfDir), 0.0);
    float vdoth = max(dot(viewDirWS, halfDir), 0.0);

    // asm 138-144: 反射向量与 ndotv(反射方向 = reflect(-V, N),URP 同构)
    float3 reflectV = 2.0 * dot(surfaceNormal, viewDirWS) * surfaceNormal - viewDirWS;
    float ndotv = max(dot(surfaceNormal, viewDirWS), 0.0);
    float ndotvClamped = min(ndotv, 1.0);                       // asm 143-144

    // asm 145-149: 派生颜色(roughness 贴图 r, metallic 贴图 g)
    float3 diffuseColor = baseColor * (1.0 - metallic);
    float3 specularColor = baseColor * metallic + 0.04 * (1.0 - metallic);
    float reflectionMip = roughness * 6.0;                      // asm 147(反射探针 mip)

    // asm 150-156: EnvBRDFApprox(Karis,常数逐条照抄;注意 297 行为 exp 自然指数)
    float4 r4x = roughness * float4(-1.0, -0.0275, -0.572, 0.022) + float4(1.0, 0.0425, 1.04, -0.04);
    float a004 = min(r4x.x * r4x.x, exp(-9.28 * ndotv)) * r4x.x + r4x.y;
    float2 envBRDF = float2(-1.04, 1.04) * a004 + r4x.zw;

    // asm 157-174: 卡通环境 ramp(ldotenvL = dot(主光, 旋转后环境光方向),翻转参考方向使夹角恒 > 90°)
    if (toonOn)
    {
        float ldotenvL = dot(lightDir, float3(_EnvLightDirMatrix._m00, _EnvLightDirMatrix._m10, _EnvLightDirMatrix._m20));  // asm 158-160
        float envSign = ldotenvL > 0.0 ? -1.0 : 1.0;            // asm 161-164
        float3 envRefDir = normalize(envSign * _EnvLightRefDir.xyz);  // asm 165-168
        float ndotEnvL = saturate(dot(surfaceNormal, envRefDir));     // asm 169
        float2 rampUV = float2(envBRDF.x * ndotEnvL, 0.625);         // asm 170-171
        envBRDF.x = SAMPLE_TEXTURE2D_LOD(_RampMap, sampler_LinearClamp, rampUV, 0.0).r;  // asm 172-173
    }

    // asm 175: envBrdf = specularColor * B + A
    float3 envBrdf = specularColor * envBRDF.y + envBRDF.x;

    // asm 176-188: 环境球谐 SH(asm 布局: vB = (xy, yz, xz, z²);
    // Unity shBr = (xy, yz, z², xz) → z/w 交换;L0 在 shA.w,与 asm dp4(n,1) 同构)
    float4 vB = float4(surfaceNormal.y * surfaceNormal.x, surfaceNormal.z * surfaceNormal.y,
                       surfaceNormal.x * surfaceNormal.z, surfaceNormal.z * surfaceNormal.z);
    float3 shL2 = float3(
        dot(float4(unity_SHBr.x, unity_SHBr.y, unity_SHBr.w, unity_SHBr.z), vB),
        dot(float4(unity_SHBg.x, unity_SHBg.y, unity_SHBg.w, unity_SHBg.z), vB),
        dot(float4(unity_SHBb.x, unity_SHBb.y, unity_SHBb.w, unity_SHBb.z), vB));
    shL2 += unity_SHC.rgb * (surfaceNormal.x * surfaceNormal.x - surfaceNormal.y * surfaceNormal.y);
    float3 envSH = SHEvalLinearL0L1(surfaceNormal, unity_SHAr, unity_SHAg, unity_SHAb) + shL2;

    // asm 189-201: 球谐细节去除(启用时用 L0+L2_xz/3 的常量亮度重归一化)
    float3 envSHClamped = max(envSH, float3(0.001, 0.001, 0.001));
    float envBrightness = dot(envSHClamped, float3(0.2127, 0.7152, 0.0722));
    float3 shConstTerm = float3(unity_SHBr.w, unity_SHBg.w, unity_SHBb.w) * (1.0 / 3.0)
                       + float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);          // asm 190-196
    float newBrightness = dot(shConstTerm, float3(0.2127, 0.7152, 0.0722));         // asm 197
    float3 newEnvSH = envSHClamped / envBrightness * newBrightness;                 // asm 198-199
    float3 resultSH = shDetailRemoval ? newEnvSH : max(envSH, 0.0);                 // asm 200-201

    // asm 202-203: 漫反射环境与主光 radiance
    float3 diffuseSH = diffuseColor * resultSH;
    float radiance = ndotl * mainShadow;

    // asm 204-215: 卡通漫反射 ramp(rampUVx = max(0.0001, dot(radiance.zzz, 1/3)≈radiance),UV.y = 0.125)
    if (toonOn)
    {
        float rampUVx = max(0.0001, dot(float3(radiance, radiance, radiance), float3(0.3333, 0.3333, 0.3333)));
        float3 rampColor = SAMPLE_TEXTURE2D_LOD(_RampMap, sampler_LinearClamp, float2(rampUVx, 0.125), 0.0).rgb;
        float brightnessScale = min(1.0, radiance / rampUVx);   // asm 210-212
        radiance = (rampUVx > 0.0001) ? rampColor * brightnessScale : rampColor;   // asm 213-214
    }

    // asm 216-239: 主光 D_GGX / V_SmithJointGGXApprox / F_Schlick(常数照抄)
    float rSqr = roughness * roughness;                          // asm 217
    float ndoth2 = ndoth * ndoth;
    float dGGX = pow(rSqr / (rSqr * rSqr * ndoth2 + (1.0 - ndoth2)), 2.0);  // asm 218-221
    dGGX = min(dGGX, 2048.0);                                    // asm 222
    float oneMinusR2 = 1.0 - rSqr;                               // asm 223
    float visA = ndotvClamped * oneMinusR2 + rSqr;               // asm 224
    float visDenom = ndotl * visA + (ndotl * oneMinusR2 + rSqr) * ndotvClamped;  // asm 225-227
    float visGGX = min(0.5 / max(visDenom, 0.0001), 1.0);        // asm 228-231
    float vdothClamp = max(1.0 - vdoth, 0.001);                  // asm 232
    float vdothPow4 = vdothClamp * vdothClamp;
    vdothPow4 *= vdothPow4;                                      // asm 233-234
    float vdothPow5 = vdothClamp * vdothPow4;                    // asm 235
    float F0 = saturate(50.0 * specularColor.g);                 // asm 236(F0 用 specularColor.g 的近似)
    float F = lerp(1.0, F0, vdothPow5);                          // asm 237-239

    // asm 240-268: 卡通高光(D 在 N=H 归一化后按 ramp 采样;否则标准 D*F*G)
    float d1 = 0.0;                                              // D1 = min((1/roughness²)², 2048)
    float3 specDFG;
    if (toonOn)
    {
        float ldoth = max(dot(lightDir, halfDir), 0.0);          // asm 241-242
        d1 = min(pow(1.0 / rSqr, 2.0), 2048.0);                  // asm 243-246
        float g1Denom = ldoth * (vdoth * oneMinusR2 + rSqr) + vdoth * (ldoth * oneMinusR2 + rSqr);  // asm 247-250
        float g1 = min(0.5 / max(g1Denom, 0.0001), 1.0);         // asm 251-254
        float dgRatio = saturate((dGGX * visGGX) / (d1 * g1));   // asm 255-259
        float3 sepcRampCol = SAMPLE_TEXTURE2D_LOD(_RampMap, sampler_LinearClamp, float2(dgRatio, 0.375), 0.0).rgb;  // asm 260-261
        specDFG = d1 * g1 * F * sepcRampCol;                     // asm 262-264
    }
    else
    {
        specDFG = dGGX * F * visGGX;                             // asm 266-267
    }

    // asm 269-275: 主光合成 = (diffuse*radiance + specular*DFG*radiance) * lightColor + occlusion * diffuseSH
    specDFG = clamp(specDFG, 0.0, 10.0);
    float3 mainLightResult = (diffuseColor * radiance + specularColor * specDFG * radiance) * lightColor;
    float3 finalCol = mainLightResult;
    finalCol += occlusion * diffuseSH;

    // ---- 附加光循环(asm 276-457) ----
    // asm 276-277: 附加光数量 = min(URP 实际数量, 材质上限 cb1[10].y)
    uint maxLights = (uint)min(_AdditionalLightsCount.x, _MaxAdditionalLights);
    float3 shadowPosWS = positionWS + geometricNormalWS * 0.005;  // asm 278(阴影位置法线偏移)
    float d1Inv = 1.0 / min(pow(1.0 / rSqr, 2.0), 2048.0);        // asm 283(1/D1,附加光卡通高光用)

    for (uint lightIndex = 0; lightIndex < maxLights; lightIndex++)
    {
        ShaolvAdditionalLightData lightData = _ShaolvAdditionalLights[lightIndex];

        // asm 294-298: 光源方向(位置光: pos - shadowPos;方向光: pos.xyz 即方向)
        float3 addiLightDir = lightData.positionAndType.xyz - shadowPosWS * lightData.positionAndType.w;
        float distSqr = dot(addiLightDir, addiLightDir);
        addiLightDir = addiLightDir * rsqrt(max(distSqr, 0.0));

        // asm 299-304: 距离衰减 = max(0, 1-(distSqr*1/range²)²)²(与 URP 公式不同,照抄)
        float distAttenParam = distSqr * lightData.rangeSpot.x;
        float distAtten = 1.0 - distAttenParam * distAttenParam;
        distAtten = max(distAtten, 0.0);
        distAtten *= distAtten;

        // asm 305-308: 角度衰减 = saturate(dot(聚光方向, 光方向)*scale + bias)²
        float angleAtten = saturate(dot(lightData.spotDir.xyz, addiLightDir) * lightData.rangeSpot.z + lightData.rangeSpot.w);
        angleAtten *= angleAtten;
        float attenuation = distAtten * angleAtten;

        // asm 309-395: 附加光阴影(URP _AdditionalShadowParams/_AdditionalLightsWorldToShadow)
        float addiShadow = ShaolvAdditionalLightShadow(shadowPosWS, lightIndex);

        // asm 384-393: ndotL / halfDir / ndotH / vdotH
        float ndotAddiL = max(dot(surfaceNormal, addiLightDir), 0.0);
        float3 halfDirAddi = normalize(viewDirWS + addiLightDir);
        float ndotAddiH = max(dot(surfaceNormal, halfDirAddi), 0.0);
        float vdotAddiH = max(dot(viewDirWS, halfDirAddi), 0.0);

        // asm 396: 附加光 radiance = ndotL * shadow
        float3 addiRadiance = ndotAddiL * addiShadow;

        // asm 397-405: 卡通漫反射 ramp(UV.y = 0.875;无主光的 >0.0001 选择,直接替换)
        if (toonOn)
        {
            float rampUVx = max(0.0001, dot(addiRadiance.zzz, float3(0.3333, 0.3333, 0.3333)));
            float3 rampColor = SAMPLE_TEXTURE2D_LOD(_RampMap, sampler_LinearClamp, float2(rampUVx, 0.875), 0.0).rgb;
            float brightnessScale = min(1.0, addiRadiance.z / rampUVx);
            addiRadiance = rampColor * brightnessScale;
        }

        // asm 406-425: 附加光 D/V/F(结构同主光,ndotl→ndotAddiL,ndoth→ndotAddiH)
        float ndotH2 = ndotAddiH * ndotAddiH;
        float dAddi = min(pow(rSqr / (rSqr * rSqr * ndotH2 + (1.0 - ndotH2)), 2.0), 2048.0);  // asm 406-411
        float visDenom2 = ndotAddiL * visA + ndotvClamped * (ndotAddiL * oneMinusR2 + rSqr);  // asm 412-414
        float visAddi = min(0.5 / max(visDenom2, 0.0001), 1.0);  // asm 415-418
        float vdotAddiClamp = max(1.0 - vdotAddiH, 0.001);       // asm 419
        float vdotAddiPow4 = vdotAddiClamp * vdotAddiClamp;
        vdotAddiPow4 *= vdotAddiPow4;                            // asm 420-422
        float vdotAddiPow5 = vdotAddiClamp * vdotAddiPow4;       // asm 423
        float FAddi = lerp(1.0, F0, vdotAddiPow5);               // asm 424-425

        // asm 426-448: 附加光卡通高光(同主光结构)
        float3 specAddi;
        if (toonOn)
        {
            float ldothAddi = max(dot(addiLightDir, halfDirAddi), 0.0);   // asm 427-428
            float g1Denom2 = ldothAddi * (vdotAddiH * oneMinusR2 + rSqr)
                           + vdotAddiH * (ldothAddi * oneMinusR2 + rSqr); // asm 429-432
            float g1Addi = min(0.5 / max(g1Denom2, 0.0001), 1.0);        // asm 433-436
            float dgRatio2 = saturate((dAddi * visAddi) * d1Inv / g1Addi); // asm 437-440
            float3 sepcRampCol2 = SAMPLE_TEXTURE2D_LOD(_RampMap, sampler_LinearClamp, float2(dgRatio2, 0.375), 0.0).rgb;  // asm 441
            specAddi = d1 * g1Addi * FAddi * sepcRampCol2;               // asm 442-444
        }
        else
        {
            specAddi = dAddi * FAddi * visAddi;                          // asm 446-447
        }

        // asm 449-455: 合成 = (diffuse*radiance + specular*DFG*radiance) * color * attenuation
        specAddi = clamp(specAddi, 0.0, 10.0);
        float3 addiResult = (diffuseColor * addiRadiance + specularColor * specAddi * addiRadiance) * lightData.color.rgb;
        finalCol += addiResult * attenuation;
    }

    // asm 458-468: 反射探针(URP unity_SpecCube0,原 t0)+ 自定义曝光 + 贴花
    float4 reflectionProbe = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectV, reflectionMip);
    float exposure = max((reflectionProbe.a - 1.0) * _ReflectionExposureBias + 1.0, 0.0);  // asm 459-461
    exposure = pow(exposure, _ReflectionExposurePow) * _ReflectionIntensity;               // asm 462-465
    finalCol += reflectionProbe.rgb * exposure * envBrdf;   // asm 466-467
    finalCol += baseColorDecal * decal;                     // asm 468(贴花: baseCol * _DecalStrength * pbr.a)

    // asm 469: 最终染色
    finalCol *= _TintColor.rgb;

    // asm 470-475: 屏幕空间偏移 = (当前 UV - 上一帧 UV) * 分辨率 + 抖动(原 cb0[6].xy/cb0[2782].xy)
    float2 oldScreenUV = input.positionCS2.xy / input.positionCS2.w * float2(0.5, -0.5) + 0.5;
    float2 screenUV = input.positionCS.xy / input.positionCS.w * float2(0.5, -0.5) + 0.5;
    output.screenOffset.xy = (screenUV - oldScreenUV) * _ScreenParams.xy + _ScreenSpaceDither.xy;

    // asm 476-478: 时间变色 lerp(finalCol, _TimeTintColor, v7.w * 强度)
    float timeMix = input.worldViewDir.w * _TimeTintColor.w;
    output.color.rgb = lerp(finalCol, _TimeTintColor.rgb, timeMix);

    // asm 479-486: 八面体法线编码(用几何翻转法线;fold 依据 n.z 符号)
    float invManhattan = rcp(dot(abs(geometricNormalWS), float3(1.0, 1.0, 1.0)));   // asm 479-480
    float2 signN = (geometricNormalWS.xy >= 0.0) ? 1.0 : -1.0;                       // asm 483
    float foldZ = saturate(-geometricNormalWS.z * invManhattan);                     // asm 482
    float2 octUV = geometricNormalWS.xy * invManhattan + signN * foldZ;              // asm 484-485
    output.normalMask.xy = octUV * 0.5 + 0.5;

    // asm 487-490: 输出常量
    output.color.a = 1.0;
    output.normalMask.z = 0.498;                                // 材质 id 常数
    output.normalMask.w = 0.5 - _WindowMaskStrength * 0.5;      // 窗户遮罩
    output.screenOffset.zw = 0.0;

    return output;
}

#endif // SHAOLV_LIGHTING_INCLUDED
