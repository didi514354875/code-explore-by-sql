// NPRCharacter/NPRCharacterGI.hlsl
// 环境光(间接光照),对应原始 asm PS skin 73-247 / face 58-228(与 cloth 的 GI 块逐字节相同):
//   _GI_MODE_VOLUME  -> 体积 GI 采样(完整移植,纹理未赋值时与回退一致,建议用 URPProbe 模式)
//   _GI_MODE_CONST   -> 固定颜色(skin/face 槽位 cb0[163].xyz;cloth 为 cb0[162].xyz,属性名统一 _SHColorConst)
//   _GI_MODE_MATCAP  -> view 空间法线采样 MatCap + 内联 HSV 调整
//   默认(URPProbe)   -> 新增:URP 全局 SH(SHEvalLinearL0L1,GlobalIllumination.hlsl:232)
// ndotSky(skin 249-251 / face 229-231):saturate(dot(NxzDir, _SkyDir.xz) + _SkyOffset) * _SkyScale + _SkyBias
//   —— 注意:skin/face 用 NxzDir(2D)× _SkyDir.xz(dp2),与 cloth 端口的 normalTWS 全向量点积不同,以各自 asm 为准。
#ifndef NPRCHARACTER_GI_INCLUDED
#define NPRCHARACTER_GI_INCLUDED

#include "NPRCharacterInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"  // GlobalIllumination.hlsl:623 需要 BRDFData
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"  // SHEvalLinearL0L1 / unity_SpecCube0

struct CharacterIndirectLight
{
    float3 shColor;          // 环境色(sh 求值结果)
    float3 originSHColor;    // 环境色原始值(gEnv 归一化用;URPProbe/Const/MatCap = 1)
    float3 dominantSHDir;    // 主方向(用于 gEnv;volume/probe 模式由 SH 系数亮度加权)
    float  dominantOn;       // 主方向是否启用(volume/probe=1,const/matcap=0)
    float  ambientIntensity; // 环境强度
    float  ndotSky;          // ndotSky 修正
};

// 体积 GI 采样结果:3 组 SH 系数(float4:xyz=L1 方向权重, w=L0 强度)
struct CharacterVolumeSH
{
    float4 sh0;
    float4 sh1;
    float4 sh2;
};

// 体积 GI 采样(skin/face asm 75-127):返回 3 组 SH 系数(渐变到 _VolumeSH0/1/2)
CharacterVolumeSH SampleCharacterVolumeGI(float3 positionWS, float dist, float blend)
{
    CharacterVolumeSH sh;
    sh.sh0 = _VolumeSH0;
    sh.sh1 = _VolumeSH1;
    sh.sh2 = _VolumeSH2;
    if (_VolumeHasIndex > 0.0 && blend < 1.0)
    {
        // 距离分级(asm 84-88):<100 用 0.0039/lod0,<200 用 0.002/lod1,否则 0.0005/lod2
        float2 distLod = float2(0.0005, 2.0);
        distLod = (dist < 200.0) ? float2(0.002, 1.0) : distLod;
        distLod = (dist < 100.0) ? float2(0.0039, 0.0) : distLod;
        float3 uvIndex = frac(positionWS * distLod.x);
        float4 index = SAMPLE_TEXTURE3D_LOD(_VolumeIndex3D, sampler_LinearClamp, uvIndex, distLod.y);
        index = floor(index * 255.0 + 0.5);      // asm 92-93: *255+0.5 取整
        if (index.w > 0.0)
        {
            // 5×5×5 细分(asm 96-99)
            float3 cell = frac(positionWS / index.w) * 4.0 + 0.5;
            float3 uvLight = (index.xyz * 5.0 + cell) * _VolumeResolution.xyz;
            float3 light = SAMPLE_TEXTURE3D_LOD(_VolumeLight3D, sampler_LinearClamp, uvLight, 0.0).xyz;
            // 低频三次采样(z×0.3333)得到 3 组方向(SH L1),rgb 为强度(L0)(asm 102-107)
            float3 lf0 = SAMPLE_TEXTURE3D_LOD(_VolumeLightLowFreq3D, sampler_LinearClamp, float3(uvLight.x, uvLight.y, uvLight.z * 0.3333), 0.0).xyz;
            float3 lf1 = SAMPLE_TEXTURE3D_LOD(_VolumeLightLowFreq3D, sampler_LinearClamp, float3(uvLight.x, uvLight.y, uvLight.z * 0.3333 + 0.3333), 0.0).xyz;
            float3 lf2 = SAMPLE_TEXTURE3D_LOD(_VolumeLightLowFreq3D, sampler_LinearClamp, float3(uvLight.x, uvLight.y, uvLight.z * 0.3333 + 0.6667), 0.0).xyz;
            sh.sh0 = float4((lf0 * 4.0 - 2.0) * light.r, light.r);   // asm 108-114: 方向 [-2,2]×强度
            sh.sh1 = float4((lf1 * 4.0 - 2.0) * light.g, light.g);
            sh.sh2 = float4((lf2 * 4.0 - 2.0) * light.b, light.b);
            // 渐变混合到全局 SH(asm 115-122)
            sh.sh0 = lerp(sh.sh0, _VolumeSH0, blend);
            sh.sh1 = lerp(sh.sh1, _VolumeSH1, blend);
            sh.sh2 = lerp(sh.sh2, _VolumeSH2, blend);
        }
    }
    return sh;
}

// dominant 方向由 SH 系数按亮度权重合成(skin/face asm 139-146)
float3 GetCharacterDominantSHDir(float4 sh0, float4 sh1, float4 sh2)
{
    float3 dir = normalize(0.2126 * sh0.xyz + 0.7152 * sh1.xyz + 0.0722 * sh2.xyz);
    dir.y = abs(dir.y);      // asm 146: 限制 y
    return dir;
}

CharacterIndirectLight GetCharacterIndirectLight(CharacterSurfaceData surface, float3 positionWS)
{
    CharacterIndirectLight gi;
    gi.shColor = 0;
    gi.originSHColor = 1;
    gi.dominantSHDir = 0;
    gi.dominantOn = 0;
    // skin/face asm 66-68:lerp(_AmbientBase, 1, cb0[171].w) * _Exposure;cb0[171].w 即 _FogEnabled
    gi.ambientIntensity = lerp(_AmbientBase, 1.0, _FogEnabled) * _Exposure;

    float3 normalTWS = surface.normalTWS;

#if defined(_GI_MODE_VOLUME)
    // skin/face asm 75-183
    float3 offset = positionWS - _VolumeOrigin.xyz;
    float dist = max(abs(offset.x), max(abs(offset.y), abs(offset.z)));
    float blend = saturate((dist - 896.0) * 0.0156);   // asm 78-79:896 内不渐变,896 外 64 距离渐变到全局
    CharacterVolumeSH sh = SampleCharacterVolumeGI(positionWS, dist, blend);

    // SHEvalLinearL0L1(skin/face asm 133-137,URP GlobalIllumination.hlsl:232 同款)
    float3 shColor = max(SHEvalLinearL0L1(normalTWS, sh.sh0, sh.sh1, sh.sh2), 0);
    gi.originSHColor = gi.ambientIntensity * shColor;   // asm 138
    gi.dominantSHDir = GetCharacterDominantSHDir(sh.sh0, sh.sh1, sh.sh2);
    // SHDominantColor/SHDominantIntensity(skin/face asm 148-154)
    float3 dominantColor = max(float3(dot(sh.sh0, float4(gi.dominantSHDir, 1)), dot(sh.sh1, float4(gi.dominantSHDir, 1)), dot(sh.sh2, float4(gi.dominantSHDir, 1))), 0);
    float dominantIntensity = max(dominantColor.x, max(dominantColor.y, dominantColor.z)) * gi.ambientIntensity;
    // asm 155-196 的 HSV 修正作用于 originSHColor(= ambientIntensity * shColor),修正结果作为后续 shColor 使用
    gi.shColor = CharacterAdjustSHColor(gi.originSHColor);
    gi.dominantOn = 1;                                      // asm 197
    gi.ambientIntensity = dominantIntensity;                // asm 198
#elif defined(_GI_MODE_CONST)
    // skin/face asm 243:cb0[163].xyz(与 cloth 的 cb0[162].xyz 槽位不同,只写注释)
    gi.shColor = _SHColorConst.xyz;
    gi.dominantSHDir = 0;
    gi.originSHColor = 1;
    gi.dominantOn = 0;
#elif defined(_GI_MODE_MATCAP)
    // skin/face asm 200-241:view 空间法线 xy -> uv,采样 MatCap(带 _MipBias),通道 swizzle yzwx
    float3 viewNormal = mul(UNITY_MATRIX_V, float4(normalTWS, 0.0)).xyz;
    float2 uvMatCap = normalize(viewNormal).xy * 0.5 + 0.5;
    float4 matCapTex = SAMPLE_TEXTURE2D_BIAS(_MatCapTex, sampler_LinearClamp, uvMatCap, _MipBias);
    float3 matCap = CharacterAdjustMatCapColor(float3(matCapTex.y, matCapTex.z, matCapTex.x));  // asm 209 的 yzwx swizzle
    gi.shColor = lerp(1.0, matCap, _MatCapMix);             // asm 240-241
    gi.dominantSHDir = 0;
    gi.originSHColor = 1;
    gi.dominantOn = 0;
#else
    // URPProbe(新增模式):URP 全局 SH 系数(GlobalIllumination.hlsl 同款),dominant 与 volume 模式同构
    gi.shColor = SHEvalLinearL0L1(normalTWS, unity_SHAr, unity_SHAg, unity_SHAb);
    gi.dominantSHDir = GetCharacterDominantSHDir(unity_SHAr, unity_SHAg, unity_SHAb);
    gi.dominantOn = 1;
    gi.originSHColor = 1;
#endif

    // ndotSky(skin 249-251 / face 229-231):saturate(dot(NxzDir, _SkyDir.xz) + _SkyOffset) * _SkyScale + _SkyBias
    //   注:dp2 仅用 NxzDir.xy × _SkyDir.xz(NxzDir 由 surface 阶段计算,face 含 faceControl.y 混合)
    gi.ndotSky = saturate(dot(surface.NxzDir, _SkyDir.xz) + _SkyOffset) * _SkyScale + _SkyBias;

    return gi;
}

#endif // NPRCHARACTER_GI_INCLUDED
