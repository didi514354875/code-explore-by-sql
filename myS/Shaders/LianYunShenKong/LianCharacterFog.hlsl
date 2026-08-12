#ifndef LIAN_CHARACTER_FOG_INCLUDED
#define LIAN_CHARACTER_FOG_INCLUDED

// 角色雾(dump `_37`,Unreal ExponentialHeightLineIntegralShared,线 3620-3690)。
// 已对照 NPRCharacterFog.hlsl:其雾为另一套引擎的 ExponentialHeightFog 数学(逐通道透射 +
// LUT hash),与本 dump 的线积分 + 3D LUT 结构不同,不复用,照 dump 内联移植。

#include "LianCharacterInput.hlsl"

/// 雾应用(dump 线 3620-3690):世界位置×100 入雾体积局部 → 线积分透射 →
/// LUT 3D 采样散射 → 方向光散射 → 混合。
float3 LianApplyFog(float3 finalLightColor, float3 positionWS)
{
    // 雾体积局部坐标(×100 缩放 + 原点偏移)
    float3 posInFog = positionWS * 100.0 - _FogVolumeOrigin.xyz;
    float distInFog = length(posInFog);
    if (distInFog < 1e-6)
        return finalLightColor;

    // 线积分(dump 线 3626-3640)
    float rayLen = max(distInFog - _FogStartDist.x, 0.0);
    float y = abs(posInFog.y) > 0.00999999977648258209228515625
        ? posInFog.y : 0.00999999977648258209228515625;
    float heightDensity = max(y * _FogDensity.y, -127.0);
    float heightFalloff = 1.0 - exp2(-heightDensity);
    float lineIntegral = heightFalloff * _FogDensity.x / heightDensity;
    float transmittance = 1.0 - exp2(-(rayLen * lineIntegral));

    // LUT 散射(dump 线 3641-3648)
    float3 dirInFog = posInFog / distInFog;
    float3 lutUV = float3(dot(dirInFog.xz, _FogWindDirA.xy), dirInFog.y, dot(dirInFog.xz, _FogWindDirA.zw));
    float3 inScattering = SAMPLE_TEXTURE3D_LOD(_FogLUT3D, sampler_FogLUT3D, lutUV, transmittance * _FogLUTDepthScale).xyz
        * _FogVolumetricAlbedo.xyz;

    // 方向光散射(dump 线 3649-3659)
    float dirFactor = 1.0 - exp2(-(max(distInFog - _FogDirStartDist, 0.0) * lineIntegral));
    float3 dirInscat = pow(saturate(dot(dirInFog, _MainLightDir)), _FogDirInscatColor.w) * _FogDirInscatColor.xyz;

    // 混合(dump 线 3660-3669)
    float blend = clamp((distInFog * 0.00999999977648258209228515625 - _FogBlendOffset) / _FogBlendScale, 0.0, 1.0);
    blend = max(transmittance, blend);
    float3 fogColor = inScattering * transmittance + dirInscat * dirFactor;
    return finalLightColor * (1.0 - blend) + fogColor;
}

#endif // LIAN_CHARACTER_FOG_INCLUDED
