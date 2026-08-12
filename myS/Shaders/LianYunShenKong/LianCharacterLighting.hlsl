#ifndef LIAN_CHARACTER_LIGHTING_INCLUDED
#define LIAN_CHARACTER_LIGHTING_INCLUDED

// 附加光求值工具(dump `_9` 六数组):自定义距离衰减曲线 + 聚光角度衰减。
// 距离衰减 = saturate(lenSq·y + z) / (lenSq·x + 1)(dump `_9._m4`);
// 角度衰减 = saturate(SdotL·x + y)²(dump `_9._m1`)。

#include "LianCharacterInput.hlsl"

/// 灯光指向表面方向(dump:`pos.xyz - positionWS·w`,w=0 为方向光)
float3 LianLightDir(int lightIndex, float3 positionWS)
{
    return _LianLightPosType[lightIndex].xyz - positionWS * _LianLightPosType[lightIndex].w;
}

/// 距离衰减(dump 线 2844-2848)
float LianLightDistanceAtten(int lightIndex, float lenSq)
{
    float denom = _LianLightDistAtten[lightIndex].x * lenSq + 1.0;
    float atten = saturate(_LianLightDistAtten[lightIndex].y * lenSq + _LianLightDistAtten[lightIndex].z);
    return atten / denom;
}

/// 角度衰减(dump 线 2849-2852)
float LianLightAngleAtten(int lightIndex, float SdotL)
{
    float atten = saturate(SdotL * _LianLightSpotAtten[lightIndex].x + _LianLightSpotAtten[lightIndex].y);
    return atten * atten;
}

#endif // LIAN_CHARACTER_LIGHTING_INCLUDED
