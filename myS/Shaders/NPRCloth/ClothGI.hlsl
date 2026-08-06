// NPRCloth/ClothGI.hlsl
// 环境光(间接光照),对应原始 asm PS 54-236:
//   _GI_MODE_VOLUME  -> asm 58-183 体积 GI 采样(完整移植,纹理未赋值时与回退一致,建议用 URPProbe 模式)
//   _GI_MODE_CONST   -> asm 228    固定颜色
//   _GI_MODE_MATCAP  -> asm 185-227 view 空间法线采样 MatCap + 内联 HSV 调整
//   默认(URPProbe)   -> 新增:URP 全局 SH(SHEvalLinearL0L1,GlobalIllumination.hlsl:232)
#ifndef NPRCLOTH_CLOTH_GI_INCLUDED
#define NPRCLOTH_CLOTH_GI_INCLUDED

#include "ClothInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"  // GlobalIllumination.hlsl:623 需要 BRDFData
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"  // SHEvalLinearL0L1 / unity_SpecCube0

struct ClothIndirectLight
{
    float3 shColor;          // 环境色(sh 求值结果)
    float3 originSHColor;    // 环境色原始值(gEnv 归一化用;URPProbe/Const/MatCap = 1)
    float3 dominantSHDir;    // 主方向(用于 gEnv;volume/probe 模式由 SH 系数亮度加权)
    float  dominantOn;       // 主方向是否启用(volume/probe=1,const/matcap=0)
    float  ambientIntensity; // 环境强度
    float  ndotSky;          // ndotSky 修正
};

// 体积 GI 采样结果:3 组 SH 系数(float4:xyz=L1 方向权重, w=L0 强度)
struct ClothVolumeSH
{
    float4 sh0;
    float4 sh1;
    float4 sh2;
};

// HSV 饱和度/亮度修正(asm 140-181,chilliant RGBtoHCV;常数 0.35/0.7 照抄):
// 亮度越高饱和度越高,色相越接近红色饱和度越低;value = 2/(2-saturation)
float3 AdjustSHColor(float3 c)
{
    // RGBtoHCV begin (https://www.chilliant.com/rgb2hsv.html)
    float4 p = (c.g < c.b) ? float4(c.b, c.g, -1.0, 2.0 / 3.0) : float4(c.g, c.b, 0.0, -1.0 / 3.0);
    float4 q = (c.r < p.x) ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float chroma = q.x - min(q.w, q.y);
    float hue = abs((q.w - q.y) / (6.0 * chroma + 0.0001) + q.z);
    float saturation = chroma / (q.x + 0.0001);
    // RGBtoHCV end
    hue = frac(abs(hue));
    // 色相到终点距离 > 0.45 的边缘部分(越接近红色饱和度越低)
    float hueEdge = smoothstep(0.0, 1.0, saturate((abs(hue - 0.5) - 0.45) * -10.0));
    float satAdjusted = min(saturation, (0.7 - 0.35 * hueEdge) * saturate(q.x));
    float valAdjusted = 2.0 / (2.0 - satAdjusted);
    // HSVTORGB begin (https://github.com/przemyslawzaworski/Unity3D-CG-programming/blob/master/hsv.shader)
    float3 hsv = frac(hue + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0;
    float3 rgb = saturate(abs(hsv) - 1.0);
    rgb = lerp(float3(1, 1, 1), rgb, satAdjusted);
    // HSVTORGB end
    return rgb * valAdjusted;
}

// 内联 HSV 调整(asm 195-224,MatCap 采样后使用;纹理通道按 asm 采样 swizzle yzwx)
float3 AdjustMatCapColor(float3 c)
{
    float4 p = (c.g < c.b) ? float4(c.b, c.g, -1.0, 2.0 / 3.0) : float4(c.g, c.b, 0.0, -1.0 / 3.0);
    float4 q = (c.r < p.x) ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float chroma = q.x - min(q.w, q.y);
    float hue = abs((q.w - q.y) / (6.0 * chroma + 0.0001) + q.z);
    float saturation = chroma / (q.x + 0.0001);
    float valAdjusted = 2.0 / (2.0 - saturation);
    float3 hsv = frac(abs(hue) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0;
    float3 rgb = saturate(abs(hsv) - 1.0);
    rgb = lerp(float3(1, 1, 1), rgb, saturation);
    return rgb * valAdjusted;
}

// 体积 GI 采样(asm 60-117):返回 3 组 SH 系数(渐变到 _VolumeSH0/1/2)
ClothVolumeSH SampleVolumeGI(float3 positionWS, float dist, float blend)
{
    ClothVolumeSH sh;
    sh.sh0 = _VolumeSH0;
    sh.sh1 = _VolumeSH1;
    sh.sh2 = _VolumeSH2;
    if (_VolumeHasIndex > 0.0 && blend < 1.0)
    {
        // 距离分级(asm 69-73):<100 用 0.0039/lod0,<200 用 0.002/lod1,否则 0.0005/lod2
        float2 distLod = float2(0.0005, 2.0);
        distLod = (dist < 200.0) ? float2(0.002, 1.0) : distLod;
        distLod = (dist < 100.0) ? float2(0.0039, 0.0) : distLod;
        float3 uvIndex = frac(positionWS * distLod.x);
        float4 index = SAMPLE_TEXTURE3D_LOD(_VolumeIndex3D, sampler_LinearClamp, uvIndex, distLod.y);
        index = floor(index * 255.0 + 0.5);      // asm 77-78: *255+0.5 取整
        if (index.w > 0.0)
        {
            // 5×5×5 细分(asm 81-85)
            float3 cell = frac(positionWS / index.w) * 4.0 + 0.5;
            float3 uvLight = (index.xyz * 5.0 + cell) * _VolumeResolution.xyz;
            float3 light = SAMPLE_TEXTURE3D_LOD(_VolumeLight3D, sampler_LinearClamp, uvLight, 0.0).xyz;
            // 低频三次采样(z×0.3333)得到 3 组方向(SH L1),rgb 为强度(L0)(asm 87-92)
            float3 lf0 = SAMPLE_TEXTURE3D_LOD(_VolumeLightLowFreq3D, sampler_LinearClamp, float3(uvLight.x, uvLight.y, uvLight.z * 0.3333), 0.0).xyz;
            float3 lf1 = SAMPLE_TEXTURE3D_LOD(_VolumeLightLowFreq3D, sampler_LinearClamp, float3(uvLight.x, uvLight.y, uvLight.z * 0.3333 + 0.3333), 0.0).xyz;
            float3 lf2 = SAMPLE_TEXTURE3D_LOD(_VolumeLightLowFreq3D, sampler_LinearClamp, float3(uvLight.x, uvLight.y, uvLight.z * 0.3333 + 0.6667), 0.0).xyz;
            sh.sh0 = float4((lf0 * 4.0 - 2.0) * light.r, light.r);   // asm 93-99: 方向 [-2,2]×强度
            sh.sh1 = float4((lf1 * 4.0 - 2.0) * light.g, light.g);
            sh.sh2 = float4((lf2 * 4.0 - 2.0) * light.b, light.b);
            // 渐变混合到全局 SH(asm 100-107)
            sh.sh0 = lerp(sh.sh0, _VolumeSH0, blend);
            sh.sh1 = lerp(sh.sh1, _VolumeSH1, blend);
            sh.sh2 = lerp(sh.sh2, _VolumeSH2, blend);
        }
    }
    return sh;
}

// dominant 方向由 SH 系数按亮度权重合成(asm 124-132)
float3 GetDominantSHDir(float4 sh0, float4 sh1, float4 sh2)
{
    float3 dir = normalize(0.2126 * sh0.xyz + 0.7152 * sh1.xyz + 0.0722 * sh2.xyz);
    dir.y = abs(dir.y);      // asm 131: 限制 y
    return dir;
}

ClothIndirectLight GetClothIndirectLight(ClothSurfaceData surface, float3 positionWS)
{
    ClothIndirectLight gi;
    gi.shColor = 0;
    gi.originSHColor = 1;
    gi.dominantSHDir = 0;
    gi.dominantOn = 0;
    gi.ambientIntensity = lerp(_AmbientBase, 1.0, 1.0) * _Exposure;  // asm 55-57(cb0[171].w 在 URP forward 恒 1)

    float3 normalTWS = surface.normalTWS;

#if defined(_GI_MODE_VOLUME)
    // asm 58-183
    float3 offset = positionWS - _VolumeOrigin.xyz;
    float dist = max(abs(offset.x), max(abs(offset.y), abs(offset.z)));
    float blend = saturate((dist - 896.0) * 0.0156);   // asm 63-64:896 内不渐变,896 外 64 距离渐变到全局
    ClothVolumeSH sh = SampleVolumeGI(positionWS, dist, blend);

    // SHEvalLinearL0L1(asm 118-122,URP GlobalIllumination.hlsl:232 同款)
    float3 shColor = max(SHEvalLinearL0L1(normalTWS, sh.sh0, sh.sh1, sh.sh2), 0);
    gi.originSHColor = gi.ambientIntensity * shColor;   // asm 123
    gi.dominantSHDir = GetDominantSHDir(sh.sh0, sh.sh1, sh.sh2);
    // SHDominantColor/SHDominantIntensity(asm 133-139)
    float3 dominantColor = max(float3(dot(sh.sh0, float4(gi.dominantSHDir, 1)), dot(sh.sh1, float4(gi.dominantSHDir, 1)), dot(sh.sh2, float4(gi.dominantSHDir, 1))), 0);
    float dominantIntensity = max(dominantColor.x, max(dominantColor.y, dominantColor.z)) * gi.ambientIntensity;
    // 注:asm 140-181 的 HSV 修正作用于 originSHColor(= ambientIntensity * shColor),修正结果作为后续 shColor 使用
    gi.shColor = AdjustSHColor(gi.originSHColor);
    gi.dominantOn = 1;                                      // asm 182
    gi.ambientIntensity = dominantIntensity;                // asm 183
#elif defined(_GI_MODE_CONST)
    // asm 228-232
    gi.shColor = _SHColorConst.xyz;
    gi.dominantSHDir = 0;
    gi.originSHColor = 1;
    gi.dominantOn = 0;
#elif defined(_GI_MODE_MATCAP)
    // asm 185-227:view 空间法线 xy -> uv,采样 MatCap(带 _MipBias),通道 swizzle yzwx
    float3 viewNormal = mul(UNITY_MATRIX_V, float4(normalTWS, 0.0)).xyz;
    float2 uvMatCap = normalize(viewNormal).xy * 0.5 + 0.5;
    float4 matCapTex = SAMPLE_TEXTURE2D_BIAS(_MatCapTex, sampler_LinearClamp, uvMatCap, _MipBias);
    float3 matCap = AdjustMatCapColor(float3(matCapTex.y, matCapTex.z, matCapTex.x));  // asm 194 的 yzwx swizzle
    gi.shColor = lerp(1.0, matCap, _MatCapMix);             // asm 225-226
    gi.dominantSHDir = 0;
    gi.originSHColor = 1;
    gi.dominantOn = 0;
#else
    // URPProbe(新增模式):URP 全局 SH 系数(GlobalIllumination.hlsl 同款),dominant 与 volume 模式同构
    gi.shColor = SHEvalLinearL0L1(normalTWS, unity_SHAr, unity_SHAg, unity_SHAb);
    gi.dominantSHDir = GetDominantSHDir(unity_SHAr, unity_SHAg, unity_SHAb);
    gi.dominantOn = 1;
    gi.originSHColor = 1;
#endif

    // ndotSky(asm 234-236):saturate(ndot + _SkyOffset) * _SkyScale + _SkyBias
    gi.ndotSky = saturate(dot(normalTWS, _SkyDir.xyz) + _SkyOffset) * _SkyScale + _SkyBias;

    return gi;
}

#endif // NPRCLOTH_CLOTH_GI_INCLUDED
