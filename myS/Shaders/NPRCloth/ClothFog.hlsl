// NPRCloth/ClothFog.hlsl
// 雾与输出(Step 8,asm PS 1107-1126 + 雾 148-333)与运动矢量编码(asm 1107-1126)。
// 解析高度雾:asm 148-200 的逐通道透射 + asm 285-333 的回退积分因子;
// LUT 雾(_FOG_LUT_3D):asm 201-283 的 3D LUT 采样与混合。
#ifndef NPRCLOTH_CLOTH_FOG_INCLUDED
#define NPRCLOTH_CLOTH_FOG_INCLUDED

#include "ClothInput.hlsl"
#include "ClothLighting.hlsl"

// ============================================================================
// 解析高度雾 + 散射(asm 148-200)
// 输入:finalColor(已曝光), positionWS, viewDirWS(表面指向相机,归一化), viewDirLen
// 输出:fogged(逐通道透射后的颜色)
// ============================================================================
float3 ApplyAnalyticFogTransmittance(float3 finalColor, float3 positionWS, float3 viewDirWS, float viewDirLen)
{
    // asm 157-158: distanceFactor = max(0, len*density - startDistance)
    float distanceFactor = max(0.0, viewDirLen * _FogDensity - _FogStartDistance);
    // asm 159-176: 高度衰减(注意 0.001 缩放是引擎世界单位,照抄)
    float curHeightDiffer = positionWS.y * 0.001 - _FogStartHeight;
    float heightDelta = (_FogEndHeight - _FogStartHeight - curHeightDiffer) / _FogHeightFalloff;
    heightDelta = max(heightDelta, 0.01);
    float heightAtten = (1.0 - exp(-1.4427 * heightDelta)) / heightDelta
        * exp(-1.4427 * curHeightDiffer / _FogHeightFalloff);
    // asm 164-165: fogColorSum = mie + rayleigh + base
    float3 fogColorSum = _FogMieColor.rgb + _FogRayleighColor.rgb + _FogBaseColor.rgb;
    // asm 177-180: 逐通道透射 T = exp(-1.4427 * fogColorSum * distanceFactor * heightAtten)
    float3 transmittance = exp(-1.4427 * fogColorSum * distanceFactor * heightAtten);
    // 散射相位(asm 163, 181-190)
    float cosTheta = dot(viewDirWS, _FogLightDir.xyz);     // asm 163(与 -viewDir 同义,见 161-162)
    float rayleighPhase = (cosTheta * cosTheta + 1.0) * 0.0597;   // asm 181-182
    float g = _FogMieG;
    float miePhase = (1.0 - g * g) / (12.5664 * pow(max(1.0 + g * g - 2.0 * g * cosTheta, 1e-6), 1.5));  // asm 183-190
    // 雾色(asm 191-199):albedo = (fogColorSum*scale + scatteringScale*(rayleigh+mie)) / fogColorSum
    float3 scattering = _FogRayleighColor.rgb * rayleighPhase + _FogMieColor.rgb * miePhase;
    float3 albedoNum = fogColorSum * _FogFinalColorScale.rgb + _FogScatteringScale.rgb * scattering;
    // 除零保护:默认全 0 时 asm 的 0/0 会产生 NaN(引擎侧恒有参数);本实现按分量钳制为 0
    float3 albedo = (fogColorSum > 1e-6) ? albedoNum / fogColorSum : 0.0;
    albedo = clamp(albedo, 0.0, 255.0);                    // asm 196-197
    // asm 198-200: fogged = finalColor*T + albedo*(1-T)
    return finalColor * transmittance + albedo * (1.0 - transmittance);
}

// 指数高度积分(asm 235-264 / 285-318 共用):band = exp(-(h-P.x)*P.z) * P.y * (1-exp(-vd*P.z))/(vd*P.z)
float HeightIntegralBand(float height, float viewDirY, float4 bandParams)
{
    // 高度项(asm 235-239 或 290-294)
    float hTerm = exp(-max((height - bandParams.x) * bandParams.z, -127.0)) * bandParams.y;
    // 视线积分(asm 240-248 或 295-303):(1 - exp(-x))/x, x -> 0 时用 0.6931 - 0.2402*x(asm 245/300 常数)
    float x = viewDirY * bandParams.z;
    float clampedX = max(x, -127.0);
    float expX = exp(-clampedX);
    float guarded = (abs(x) > 0.0) ? (1.0 - expX) / clampedX : (0.6931 - 0.2402 * clampedX);
    return hTerm * guarded;
}

// 雾因子与雾色(asm 201-333):_FOG_LUT_3D 关键字下走 LUT 路径,否则回退积分路径
void GetClothFogFactor(float3 positionWS, float3 viewDirWS, float viewDirLen, float4 positionCS,
                       out float fogFactor, out float3 fogColor)
{
#if defined(_FOG_LUT_3D)
    // ---- LUT 路径(asm 201-283) ----
    // z 分量(asm 203-206):log(posCS.w * Params5.x + Params5.y) * Params5.z / Params4.z
    float logZ = log(positionCS.w * _FogLUTParams5.x + _FogLUTParams5.y) * _FogLUTParams5.z / _FogLUTParams4.z;
    // hash 抖动(asm 207-219):cb0[88].w & 7 用 _MipBias 的整型位
    uint seed = asuint(_MipBias) & 7u;
    uint2 sp = uint2(positionCS.xy);
    uint3 s = uint3(sp.x, sp.y, seed) * 0x0019660Du + 0x3C776F2Au;
    uint a = s.y * s.z + s.x;
    uint b = s.z * a + s.y;
    uint c = a * b + s.z;
    uint d = b * c + a;
    uint e = c * d + b;
    float2 hash01 = float2(float(d >> 16), float(e >> 16)) - 1.0;
    float2 uvLUT = (positionCS.xy + _FogLUTParams8.w * hash01) * _FogLUTParams6.xy;

    // forwardFactor 与视线拆分(asm 220-234)
    float3 cameraDir = UNITY_MATRIX_V._13_23_33;
    float forwardFactor = dot(-viewDirWS, -cameraDir);       // asm 220
    float invForward = (forwardFactor > 0.0) ? rcp(forwardFactor) : 0.0;   // asm 221-223
    invForward *= _FogLUTParams4.w;                          // asm 224
    float3 viewDirRaw = positionWS - _WorldSpaceCameraPos;   // asm 225(表面指向相机)
    float lenSqr = dot(viewDirRaw, viewDirRaw);
    float invLen = rsqrt(max(lenSqr, 1e-6));
    float len = lenSqr * invLen;                             // asm 229
    float camHitY = _WorldSpaceCameraPos.y + viewDirRaw.y * (invForward * invLen);  // asm 230-231
    float viewDirYSplit = viewDirRaw.y * (1.0 - invForward * invLen);               // asm 232
    float splitFactor = len * (1.0 - invForward * invLen);                          // asm 233-234

    // 高度带积分(asm 235-264)
    float band1 = HeightIntegralBand(camHitY, viewDirYSplit, _FogLUTParams0);
    float band2 = HeightIntegralBand(camHitY, viewDirYSplit, _FogLUTParams3);
    float heightIntegral = (_FogLUTParams3.y > 0.0) ? (band1 + band2) : band1;     // asm 263-264
    fogFactor = exp(-splitFactor * heightIntegral);          // asm 265-266
    fogFactor = clamp(fogFactor, _FogLUTParams2.w, 1.0);     // asm 267-268
    // 距离积分(asm 269-274)
    fogFactor += saturate((_FogLUTParams1.x - len) * _FogLUTParams1.y);
    fogFactor += saturate((len - _FogLUTParams1.z) * _FogLUTParams1.w);
    fogFactor = min(fogFactor, 1.0);
    float3 analyticFogColor = (1.0 - fogFactor) * _FogLUTParams2.rgb;   // asm 275-276
    // LUT 采样与混合(asm 277-283)
    float4 lut = SAMPLE_TEXTURE3D_LOD(_FogLUT3D, sampler_LinearClamp, float3(uvLUT, logZ), 0.0);
    float threshold = saturate((positionCS.w - _FogLUTParams7.z) * 1000000.0);   // asm 278-279
    lut = lerp(float4(0, 0, 0, 1), lut, threshold);          // asm 280-281
    fogColor = lut.rgb + analyticFogColor * lut.a;           // asm 282
    fogFactor *= lut.a;                                      // asm 283
#else
    // ---- 回退积分路径(asm 285-333) ----
    float3 viewDirRaw = positionWS - _WorldSpaceCameraPos;
    float lenSqr = dot(viewDirRaw, viewDirRaw);
    float invLen = rsqrt(max(lenSqr, 1e-6));
    float len = lenSqr * invLen;
    float3 camPos = _WorldSpaceCameraPos;
    float band1 = HeightIntegralBand(camPos.y, viewDirRaw.y, _FogLUTParams0);
    float band2 = HeightIntegralBand(camPos.y, viewDirRaw.y, _FogLUTParams3);
    float heightIntegral = (_FogLUTParams3.y > 0.0) ? (band1 + band2) : band1;    // asm 318-319
    fogFactor = exp(-len * heightIntegral);                  // asm 320-321
    fogFactor = clamp(fogFactor, _FogLUTParams2.w, 1.0);     // asm 322-323
    fogFactor += saturate((_FogLUTParams1.x - len) * _FogLUTParams1.y);           // asm 324-325
    fogFactor += saturate((len - _FogLUTParams1.z) * _FogLUTParams1.w);           // asm 326-327
    fogFactor = min(fogFactor, 1.0);                         // asm 328-330
    fogColor = (1.0 - fogFactor) * _FogLUTParams2.rgb;       // asm 331-332
#endif
}

// ============================================================================
// 输出(asm 144-146, 334-336):finalColor = mainlightResultColor / _Exposure;雾后 o0.xyz = fogged;
// o0.a = _AlphaMode == 1 ? baseColor.a : 1
// ============================================================================
float4 ClothOutput(ClothVaryings input, ClothSurfaceData s, float3 mainlightResultColor)
{
    float3 finalColor = mainlightResultColor / _Exposure;    // asm 144
    float3 viewDirRaw = _WorldSpaceCameraPos - input.positionWS;
    float viewDirLen = length(viewDirRaw);
    float3 viewDirWS = viewDirRaw / viewDirLen;              // 表面指向相机(asm 150-154,正交由 URP 归一化视图方向替代)
    float3 fogged = ApplyAnalyticFogTransmittance(finalColor, input.positionWS, viewDirWS, viewDirLen);
    float fogFactor;
    float3 fogColor;
    GetClothFogFactor(input.positionWS, viewDirWS, viewDirLen, input.positionCS, fogFactor, fogColor);
    float3 outColor = fogged * fogFactor + fogColor;         // asm 334
    float outAlpha = (_AlphaMode == 1.0) ? s.baseAlpha : 1.0;  // asm 145-146
    return float4(outColor, outAlpha);
}

// 运动矢量编码(asm 1107-1126):delta = (pos.xy/pos.z - old.xy/old.z) * (0.5, -0.5);
// enc = sign(delta) * sqrt(|delta|) * 0.5 + 0.5;输出 (enc.xy, 1, 0.4)
float4 EncodeClothMotionVector(float3 nonJitterScreenPos, float3 oldScreenPos)
{
    float2 pos = nonJitterScreenPos.xy / max(nonJitterScreenPos.z, 0.0);
    float2 old = oldScreenPos.xy / max(oldScreenPos.z, 0.0);
    float2 delta = (pos - old) * float2(0.5, -0.5);          // asm 342-343
    float2 enc = sign(delta) * sqrt(abs(delta)) * 0.5 + 0.5; // asm 343-351
    return float4(enc, 1.0, 0.4);
}

// ============================================================================
// Fragment 入口(Forward pass)
// ============================================================================
float4 ClothFrag(ClothVaryings input, float isFrontFace : VFACE) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    ClothSurfaceData s = GetClothSurfaceData(input, isFrontFace);
    ClothIndirectLight gi = GetClothIndirectLight(s, input.positionWS);
    ClothLightingState st;
    float3 mainlightResultColor = ClothLighting(input, s, gi, st);
    ApplyAdditionalLights(input, s, st, mainlightResultColor);
    return ClothOutput(input, s, mainlightResultColor);
}

// ============================================================================
// Fragment 入口(运动矢量 pass,LightMode = ClothMotionVectors)
// ============================================================================
float4 ClothFragMotionVector(ClothVaryings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
#if defined(_MOTION_VECTOR_PASS)
    return EncodeClothMotionVector(input.nonJitterScreenPos, input.oldScreenPos);
#else
    return 0;
#endif
}

#endif // NPRCLOTH_CLOTH_FOG_INCLUDED
