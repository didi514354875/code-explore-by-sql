// NPRCloth/ClothRain.hlsl
// 雨滴湿润模块,对应原始 asm PS 237-387。动态分支 if (rainAreaMask > 0.0001)(asm 250 的 if_nz),不建关键字。
#ifndef NPRCLOTH_CLOTH_RAIN_INCLUDED
#define NPRCLOTH_CLOTH_RAIN_INCLUDED

#include "ClothInput.hlsl"
#include "ClothVertex.hlsl"

// 三方向采样混合(asm 261-276):positionOS 作为 UV(tiling),normalOS 权重归一化
float4 GetDropControl(float3 positionOS, float3 normalOS, float tiling)
{
    // asm 261-263: 雨 UV Y 翻转(FlipRainY 时 positionOS -> (x, z, -y))
    float3 rainPos = _FlipRainY > 0.5 ? float3(positionOS.x, positionOS.z, -positionOS.y) : positionOS;
    float3 rainNormal = _FlipRainY > 0.5 ? normalOS.xzy : normalOS;   // asm 264
    float3 posUV = rainPos * tiling;
    // asm 265-270: normalOSUV = max(|normalOS| - 0.2, 0)^3 归一化
    float3 nuv = max(abs(rainNormal) - 0.2, 0.0);
    nuv = nuv * nuv * nuv;
    nuv /= max(dot(nuv, float3(1, 1, 1)), 1e-6);
    // asm 271-276: 三方向采样(xz/xy/zy)按权重混合
    float4 sXZ = SAMPLE_TEXTURE2D_BIAS(_RainDropTex, sampler_LinearRepeat, posUV.xz, _MipBias);
    float4 sXY = SAMPLE_TEXTURE2D_BIAS(_RainDropTex, sampler_LinearRepeat, posUV.xy, _MipBias);
    float4 sZY = SAMPLE_TEXTURE2D_BIAS(_RainDropTex, sampler_LinearRepeat, posUV.zy, _MipBias);
    return sZY * nuv.x + sXZ * nuv.y + sXY * nuv.z;
}

// 水流法线与遮罩(asm 309-330)
void GetFlowNormalAndMask(float3 positionOS, float3 normalOS, float tiling, float flowSpeed,
                          out float3 flowN, out float flowMask)
{
    // asm 311-320: normalOSXZ = max(|normalize(normalOS.xz)| - 0.2, 0)^3 归一化(2D)
    float2 nxz = normalize(normalOS.xz);
    float2 nw = max(abs(nxz) - 0.2, 0.0);
    nw = nw * nw * nw;
    nw /= max(dot(nw, float2(1, 1)), 1e-6);

    float3 rainPos = _FlipRainY > 0.5 ? float3(positionOS.x, positionOS.z, -positionOS.y) : positionOS;
    float3 posUV = rainPos * tiling;
    // asm 321-322: 双方向采样水流法线(zy / xy)
    float3 sZY = SAMPLE_TEXTURE2D_BIAS(_RainFlowTex, sampler_LinearRepeat, posUV.zy, _MipBias).xyz;
    float3 sXY = SAMPLE_TEXTURE2D_BIAS(_RainFlowTex, sampler_LinearRepeat, posUV.xy, _MipBias).xyz;
    flowN = sZY * nw.x + sXY * nw.y;                     // asm 327-328(nw = (x权重, z权重))
    // asm 323-326, 329-330: 遮罩采样(uv 加 flowSpeed 偏移),mask1 = (x, y|z)+speed, mask2 = (z|-y, y|z)+speed
    float2 mask1UV = float2(posUV.x, posUV.y) + float2(0.0, flowSpeed);
    float2 mask2UV = float2(posUV.z, posUV.y) + float2(0.0, flowSpeed);
    float mask1 = SAMPLE_TEXTURE2D_BIAS(_RainFlowTex, sampler_LinearRepeat, mask1UV, _MipBias).a;
    float mask2 = SAMPLE_TEXTURE2D_BIAS(_RainFlowTex, sampler_LinearRepeat, mask2UV, _MipBias).a;
    flowMask = nw.y * mask1 + nw.x * mask2;              // asm 329-330
}

// 雨湿润处理(asm 237-387):修改 baseColor/shadowBaseColor/roughness/normalTWS,输出 wetFactor/wetRoughness
void ApplyRain(ClothVaryings input, inout ClothSurfaceData surface)
{
    // 雨区域(asm 237-249):xyControl = lerp(_RainAreaCenter.xy, _RainAreaControl.yw, blend)
    //   距离差 lerp(_RainAreaCenter.z, 1, blend)(原始带实例偏移,本实现无实例数据)
    float2 xyControl = lerp(_RainAreaCenter.xy, _RainAreaControl.yw, _RainAreaControl.x);
    float distanceFactor = lerp(_RainAreaCenter.z, 1.0, _RainAreaControl.x);
    float heightFactor = smoothstep(0.0, 1.0, saturate((xyControl.y - input.positionWS.y + 0.2) * 2.8571));
    float mask = distanceFactor * heightFactor;                    // asm 248 (r8.w)
    float rainOn = xyControl.x + mask;                             // asm 249-250 分支条件
    if (rainOn > 0.0001)
    {
        float metallic = surface.metallic;
        float roughness = surface.roughness;

        // asm 252-259: diffuseIntensity 相关的暗部 mask
        float3 diffuse = (1.0 - metallic) * surface.baseColor;
        float diffIntensity = ClothLuminance(diffuse);
        float diffSS = smoothstep(0.0, 1.0, saturate((diffIntensity - 0.35) * -4.0));

        // asm 260-268: 方向/距离影响
        float norY = surface.normalTWS.y * 0.2;
        float4 dropControl = GetDropControl(input.positionOS, input.normalOS, _RainAreaControl.z);
        float dirAffect = smoothstep(0.0, 1.0, saturate((((1.0 - metallic) * _RainAreaControl.x + norY) - (0.8 - dropControl.w)) * 3.3333));   // asm 278-283
        float distanceAffect = smoothstep(0.0, 1.0, saturate((saturate((1.0 - metallic) * mask) - (0.45 - dropControl.w)) * 1.5385));        // asm 284-289
        float noiseWetness = max(dirAffect, distanceAffect);       // asm 290

        float dotD = max(_RainAreaControl.x, mask);                // asm 291

        // asm 292-302: waterDot
        float metallicSS = smoothstep(0.0, 1.0, saturate((metallic - 0.5) * 4.0));
        float smoothSS = smoothstep(0.0, 1.0, saturate((0.7 - (1.0 - roughness)) * -10.0));
        float waterDot = min(metallicSS + smoothSS, 1.0);

        // asm 303-308: 水点法线扰动 + waterDotAffect(注:asm 用 (1 - dropControl.z),与计划文字有出入,以指令为准)
        float2 dotN = dropControl.xy * 2.0 - 1.0;
        float waterDotAffect = smoothstep(0.0, 1.0, saturate((waterDot * dotD - (1.0 - dropControl.z)) * 10.0));

        // asm 309-330: 水流
        float flowSpeed = _Time.y * _RainFlowSpeed * _RainAreaControl.z * 0.75;
        float3 flowN;
        float flowMask;
        GetFlowNormalAndMask(input.positionOS, input.normalOS, _RainAreaControl.z, flowSpeed, flowN, flowMask);
        float2 dotN2 = (flowN.xy * 2.0 - 1.0) * flowMask + dotN;    // asm 331-332

        // asm 333-339: waterdotAff = max(水滴, 水流)
        float waterdotAff2 = smoothstep(0.0, 1.0, saturate((waterDot * dotD - (1.0 - flowN.z)) * 10.0));
        float waterdotAff = max(waterDotAffect, waterdotAff2);

        // asm 340-345: perturbN = normalize(-z, 0, x) 归一化(退化时 (-1,0,0))
        float3 rawPerturb = float3(-surface.normalTWS.z, 0.0, surface.normalTWS.x);
        float perturbLenSqr = dot(rawPerturb.xz, rawPerturb.xz);
        float3 perturbN = (perturbLenSqr > 0.0001) ? -normalize(rawPerturb) : float3(-1, 0, 0);

        // asm 346-353: binormalPer + pertrub1(注意 surface.normalTWS 已含 faceFlip,asm 348 的 normalTWS*faceFlip 即翻转后法线)
        float3 binormalPer = cross(surface.normalTWS, perturbN);
        float3 pertrub1 = surface.normalTWS + (perturbN - surface.normalTWS) * dotN2.x;
        // asm 350-351, 357-361: 先沿 binormalPer 混合 y 分量,再按 waterdotAff 混合并归一化
        float3 perturbNormal = lerp(surface.normalTWS, lerp(pertrub1, binormalPer, dotN2.y), waterdotAff);
        surface.normalTWS = normalize(perturbNormal);               // asm 357-361

        // asm 354-356: wetRoughness = lerp(roughness, min(roughness, 0.05), waterdotAff)
        float wetRoughness = lerp(roughness, min(roughness, 0.05), waterdotAff);

        // asm 362-371: baseColorM = lerp(baseColor, baseColor * adjustIntensity, metallicSS * waterdotAff)
        float bIntensity = ClothLuminance(surface.baseColor);
        float adjustIntensity = 1.0 + 0.5 * smoothstep(0.0, 1.0, saturate((bIntensity - 0.7) * -2.5));
        float3 baseColorM = lerp(surface.baseColor, surface.baseColor * adjustIntensity, metallicSS * waterdotAff);

        // asm 372-378: darkenFactor = 1 - 0.5 * (1-diffSS) * (1-smoothSS) * noiseWetness
        float darkenFactor = 1.0 - 0.5 * (1.0 - diffSS) * (1.0 - smoothSS) * noiseWetness;
        surface.baseColor = baseColorM * darkenFactor;
        surface.shadowBaseColor *= darkenFactor;

        // asm 379-382: 粗糙度额外修正
        surface.roughness = max(wetRoughness - 0.2 * diffSS * noiseWetness, min(wetRoughness, 0.2));

        surface.wetFactor = waterdotAff;
        surface.wetRoughness = wetRoughness;
    }
    else
    {
        // asm 383-386: 法线不变、wetFactor=0、wetRoughness=0.01
        surface.wetFactor = 0.0;
        surface.wetRoughness = 0.01;
    }
}

#endif // NPRCLOTH_CLOTH_RAIN_INCLUDED
