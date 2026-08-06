// NPRCharacter/NPRCharacterFog.hlsl
// 雾(skin asm 953-1140 / face 1140-1328 / cloth 941-1082 相同)+ 运动矢量编码(skin 1142-1158 / face 1329-1346)。
// 与 ClothFog.hlsl 的差异:整体包在 _FogEnabled < 0.5 门内(asm cb0[171].w < 0.5 时执行雾,
// _FogEnabled 即该槽位,C# 默认置 1=关,ClothFogVolume 挂载时置 0)。
// 解析高度雾:asm 逐通道透射 + 回退积分因子;LUT 雾(_FOG_LUT_3D):3D LUT 采样与混合。
// frag 入口不在此文件(skin/face 各在自己 lighting 文件定义,因主光函数名不同)。
#ifndef NPRCHARACTER_FOG_INCLUDED
#define NPRCHARACTER_FOG_INCLUDED

#include "NPRCharacterInput.hlsl"
#include "NPRCharacterLighting.hlsl"

// ============================================================================
// 解析高度雾 + 散射(skin/face asm 963-1006)
// 输入:finalColor(已曝光), positionWS, viewDirWS(表面指向相机,归一化), viewDirLen
// 输出:fogged(逐通道透射后的颜色)
// ============================================================================
float3 ApplyCharacterFogTransmittance(float3 finalColor, float3 positionWS, float3 viewDirWS, float viewDirLen)
{
    // asm 963-964: distanceFactor = max(0, len*density - startDistance)
    float distanceFactor = max(0.0, viewDirLen * _FogDensity - _FogStartDistance);
    // asm 965-982: 高度衰减(注意 0.001 缩放是引擎世界单位,照抄)
    float curHeightDiffer = positionWS.y * 0.001 - _FogStartHeight;
    float heightDelta = (_FogEndHeight - _FogStartHeight - curHeightDiffer) / _FogHeightFalloff;
    heightDelta = max(heightDelta, 0.01);
    float heightAtten = (1.0 - exp(-1.4427 * heightDelta)) / heightDelta
        * exp(-1.4427 * curHeightDiffer / _FogHeightFalloff);
    // asm 970-971: fogColorSum = mie + rayleigh + base
    float3 fogColorSum = _FogMieColor.rgb + _FogRayleighColor.rgb + _FogBaseColor.rgb;
    // asm 983-986: 逐通道透射 T = exp(-1.4427 * fogColorSum * distanceFactor * heightAtten)
    float3 transmittance = exp(-1.4427 * fogColorSum * distanceFactor * heightAtten);
    // 散射相位(asm 969, 987-996)
    float cosTheta = dot(viewDirWS, _FogLightDir.xyz);     // asm 969(与 -viewDir 同义,见 961-962)
    float rayleighPhase = (cosTheta * cosTheta + 1.0) * 0.0597;   // asm 987-988
    float g = _FogMieG.w;   // asm 989-996:cb0[132].w(注意 .w 而非隐式截断的 .x)
    float miePhase = (1.0 - g * g) / (12.5664 * pow(max(1.0 + g * g - 2.0 * g * cosTheta, 1e-6), 1.5));  // asm 989-996
    // 雾色(asm 997-1003):albedo = (fogColorSum*scale + scatteringScale*(rayleigh+mie)) / fogColorSum
    float3 scattering = _FogRayleighColor.rgb * rayleighPhase + _FogMieColor.rgb * miePhase;
    float3 albedoNum = fogColorSum * _FogFinalColorScale.rgb + _FogScatteringScale.rgb * scattering;
    // 除零保护:默认全 0 时 asm 的 0/0 会产生 NaN(引擎侧恒有参数);本实现按分量钳制为 0
    float3 albedo = (fogColorSum > 1e-6) ? albedoNum / fogColorSum : 0.0;
    albedo = clamp(albedo, 0.0, 255.0);                    // asm 1002-1003
    // asm 1004-1006: fogged = finalColor*T + albedo*(1-T)
    return finalColor * transmittance + albedo * (1.0 - transmittance);
}

// 指数高度积分(asm 1041-1054 / 1096-1109 共用):band = exp(-(h-P.x)*P.z) * P.y * (1-exp(-vd*P.z))/(vd*P.z)
float CharacterHeightIntegralBand(float height, float viewDirY, float4 bandParams)
{
    // 高度项(asm 1041-1045 或 1096-1100)
    float hTerm = exp(-max((height - bandParams.x) * bandParams.z, -127.0)) * bandParams.y;
    // 视线积分(asm 1046-1053 或 1101-1108):(1 - exp(-x))/x, x -> 0 时用 0.6931 - 0.2402*x
    float x = viewDirY * bandParams.z;
    float clampedX = max(x, -127.0);
    float expX = exp(-clampedX);
    float guarded = (abs(x) > 0.0) ? (1.0 - expX) / clampedX : (0.6931 - 0.2402 * clampedX);
    return hTerm * guarded;
}

// 雾因子与雾色(skin/face asm 1007-1139):_FOG_LUT_3D 关键字下走 LUT 路径,否则回退积分路径
void GetCharacterFogFactor(float3 positionWS, float3 viewDirWS, float viewDirLen, float4 positionCS,
                           inout float fogFactor, inout float3 fogColor)
{
#if defined(_FOG_LUT_3D)
    // ---- LUT 路径(asm 1009-1089) ----
    // z 分量(asm 1009-1012):log(posCS.w * Params5.x + Params5.y) * Params5.z / Params4.z
    float logZ = log(positionCS.w * _FogLUTParams5.x + _FogLUTParams5.y) * _FogLUTParams5.z / _FogLUTParams4.z;
    // hash 抖动(asm 1013-1025):cb0[88].w & 7 用 _MipBias 的整型位
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

    // forwardFactor 与视线拆分(asm 1026-1040)
    float3 cameraDir = UNITY_MATRIX_V._13_23_33;
    float forwardFactor = dot(-viewDirWS, -cameraDir);       // asm 1026
    float invForward = (forwardFactor > 0.0) ? rcp(forwardFactor) : 0.0;   // asm 1027-1030
    invForward *= _FogLUTParams4.w;                          // asm 1030
    float3 viewDirRaw = positionWS - _WorldSpaceCameraPos;   // asm 1031(表面指向相机)
    float lenSqr = dot(viewDirRaw, viewDirRaw);
    float invLen = rsqrt(max(lenSqr, 1e-6));
    float len = lenSqr * invLen;                             // asm 1035
    float camHitY = _WorldSpaceCameraPos.y + viewDirRaw.y * (invForward * invLen);  // asm 1036-1037
    float viewDirYSplit = viewDirRaw.y * (1.0 - invForward * invLen);               // asm 1038
    float splitFactor = len * (1.0 - invForward * invLen);                          // asm 1039-1040

    // 高度带积分(asm 1041-1070)
    float band1 = CharacterHeightIntegralBand(camHitY, viewDirYSplit, _FogLUTParams0);
    float band2 = CharacterHeightIntegralBand(camHitY, viewDirYSplit, _FogLUTParams3);
    float heightIntegral = (_FogLUTParams3.y > 0.0) ? (band1 + band2) : band1;     // asm 1069-1070
    fogFactor = exp(-splitFactor * heightIntegral);          // asm 1071-1072
    fogFactor = clamp(fogFactor, _FogLUTParams2.w, 1.0);     // asm 1073-1074
    // 距离积分(asm 1075-1080)
    fogFactor += saturate((_FogLUTParams1.x - len) * _FogLUTParams1.y);
    fogFactor += saturate((len - _FogLUTParams1.z) * _FogLUTParams1.w);
    fogFactor = min(fogFactor, 1.0);
    float3 analyticFogColor = (1.0 - fogFactor) * _FogLUTParams2.rgb;   // asm 1081-1082
    // LUT 采样与混合(asm 1083-1089)
    float4 lut = SAMPLE_TEXTURE3D_LOD(_FogLUT3D, sampler_LinearClamp, float3(uvLUT, logZ), 0.0);
    float threshold = saturate((positionCS.w - _FogLUTParams7.z) * 1000000.0);   // asm 1084-1085
    lut = lerp(float4(0, 0, 0, 1), lut, threshold);          // asm 1086-1087
    fogColor = lut.rgb + analyticFogColor * lut.a;           // asm 1088
    fogFactor *= lut.a;                                      // asm 1089
#else
    // ---- 回退积分路径(asm 1091-1139) ----
    float3 viewDirRaw = positionWS - _WorldSpaceCameraPos;
    float lenSqr = dot(viewDirRaw, viewDirRaw);
    float invLen = rsqrt(max(lenSqr, 1e-6));
    float len = lenSqr * invLen;
    float3 camPos = _WorldSpaceCameraPos;
    float band1 = CharacterHeightIntegralBand(camPos.y, viewDirRaw.y, _FogLUTParams0);
    float band2 = CharacterHeightIntegralBand(camPos.y, viewDirRaw.y, _FogLUTParams3);
    float heightIntegral = (_FogLUTParams3.y > 0.0) ? (band1 + band2) : band1;    // asm 1124-1125
    fogFactor = exp(-len * heightIntegral);                  // asm 1126-1127
    fogFactor = clamp(fogFactor, _FogLUTParams2.w, 1.0);     // asm 1128-1129
    fogFactor += saturate((_FogLUTParams1.x - len) * _FogLUTParams1.y);           // asm 1130-1131
    fogFactor += saturate((len - _FogLUTParams1.z) * _FogLUTParams1.w);           // asm 1132-1133
    fogFactor = min(fogFactor, 1.0);                         // asm 1134-1136
    fogColor = (1.0 - fogFactor) * _FogLUTParams2.rgb;       // asm 1137-1138
#endif
}

// ============================================================================
// 雾入口(skin asm 953-1140 / face 1140-1328):color 为曝光后主光+附加光累计色。
// asm cb0[171].w < 0.5 才执行雾;_FogEnabled 即该槽位(C# ClothFrameData 默认置 1=关)。
// ============================================================================
float3 ApplyCharacterFog(float3 color, CharacterVaryings input)
{
    if (_FogEnabled >= 0.5)   // asm skin 953 / face 1140:cb0[171].w < 0.5 才执行雾
        return color;
    float3 viewDirRaw = _WorldSpaceCameraPos - input.positionWS;
    float viewDirLen = length(viewDirRaw);
    float3 viewDirWS = viewDirRaw / viewDirLen;              // 表面指向相机(正交由 URP 归一化视图方向替代)
    float3 fogged = ApplyCharacterFogTransmittance(color, input.positionWS, viewDirWS, viewDirLen);
    // inout 初值:消除 DXC 对 out 参数的"可能未初始化"警告
    float fogFactor = 1.0;
    float3 fogColor = 0.0;
    GetCharacterFogFactor(input.positionWS, viewDirWS, viewDirLen, input.positionCS, fogFactor, fogColor);
    return fogged * fogFactor + fogColor;                    // asm skin 1140 / face 1327
}

// 运动矢量编码(skin 1142-1158 / face 1329-1346):delta = (pos.xy/pos.z - old.xy/old.z) * (0.5, -0.5);
// enc = sign(delta) * sqrt(|delta|) * 0.5 + 0.5;输出 (enc.xy, 1, 0.4)
float4 EncodeCharacterMotionVector(float3 nonJitterScreenPos, float3 oldScreenPos)
{
    float2 pos = nonJitterScreenPos.xy / max(nonJitterScreenPos.z, 0.0);
    float2 old = oldScreenPos.xy / max(oldScreenPos.z, 0.0);
    float2 delta = (pos - old) * float2(0.5, -0.5);          // asm 1146-1147
    float2 enc = sign(delta) * sqrt(abs(delta)) * 0.5 + 0.5; // asm 1148-1155
    return float4(enc, 1.0, 0.4);
}

#endif // NPRCHARACTER_FOG_INCLUDED
