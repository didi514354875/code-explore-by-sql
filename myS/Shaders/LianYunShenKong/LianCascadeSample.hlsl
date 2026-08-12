#ifndef LIAN_CASCADE_SAMPLE_INCLUDED
#define LIAN_CASCADE_SAMPLE_INCLUDED

// 级联阴影求值共享(dump `_96` 的级联选择 + 5×5 手动 PCF),pass 6 与 pass 12 共用。
// 全局量名 = LianFrameData.cs 契约名;使用前需 include Core.hlsl + DeclareDepthTexture.hlsl。

TEXTURE2D_ARRAY(_LianShadowAtlasTex);
SAMPLER(sampler_LianShadowAtlasTex);

float4 _LianWorldToShadow[20];        // _34._m0 行序
float4 _LianCascadeSphereRadiiSq;     // _34._m8
float4 _LianCascadeClipDistances;     // _34._m9
float3 _LianCascadeCenter0;           // _34._m4
float3 _LianCascadeCenter1;           // _34._m5
float3 _LianCascadeCenter2;           // _34._m6
float4 _LianShadowMapTexel;           // _34._m17: xy=1/size, zw=size
float _LianCascadeDither[16];         // _34._m3
float4 _LianSpecialWorldToShadow[4];  // _23._m2 / _20._m0 行序
float2 _LianCascadeMaskSize;          // _38._m0: 1/4 分辨率 RT 像素尺寸
float4 _LianCameraDepthTexelSize;     // _38._m2.xy: 相机深度 texel 尺寸

/// <summary>
/// 返回平方后的 5×5 PCF 级联阴影(dump `_96` 全流程)。
/// useDither=true 时用 Bayer 抖动换级联(pass 6);false 为精确版本(pass 12)。
/// </summary>
float LianCascadeShadowValue(float2 uv, float depth, float3 worldPos, bool useDither)
{
    float3 scaledDir = worldPos;

    // ---- 特殊光 UV 有效性 ----
    float2 specialUV = _LianSpecialWorldToShadow[0].xy * scaledDir.x
                     + _LianSpecialWorldToShadow[1].xy * scaledDir.y
                     + _LianSpecialWorldToShadow[2].xy * scaledDir.z
                     + _LianSpecialWorldToShadow[3].xy;
    specialUV = specialUV * 2.0 - 1.0;
    bool specialValid = abs(specialUV.x) < 0.9900000095367431640625
                     && abs(specialUV.y) < 0.9900000095367431640625;
    float specialValidF = specialValid ? 1.0 : 0.0;
    float invValidity = 1.0 - specialValidF;

    // ---- 球心距离 / 级联选择 ----
    float dSq0 = dot(worldPos - _LianCascadeCenter0, worldPos - _LianCascadeCenter0);
    float dSq1 = dot(worldPos - _LianCascadeCenter1, worldPos - _LianCascadeCenter1);
    float dSq2 = dot(worldPos - _LianCascadeCenter2, worldPos - _LianCascadeCenter2);
    float dSqCam = dot(worldPos - _WorldSpaceCameraPos.xyz, worldPos - _WorldSpaceCameraPos.xyz);
    bool tooFar = dSqCam >= _LianCascadeClipDistances.w;

    // bool 比较 → 1 - step(edge, x) = x < edge(逐位一致)
    float3 inside = float3(1.0 - step(_LianCascadeSphereRadiiSq.x, dSq0),
                           1.0 - step(_LianCascadeSphereRadiiSq.y, dSq1),
                           1.0 - step(_LianCascadeSphereRadiiSq.z, dSq2));
    float3 toSphere = float3(dSq0, dSq1, dSq2) / _LianCascadeSphereRadiiSq.xyz;
    float3 outClip = float3(step(_LianCascadeClipDistances.x, dSq0),
                            step(_LianCascadeClipDistances.y, dSq1),
                            step(_LianCascadeClipDistances.z, dSq2));

    // dump:blend = max((-valid, -in0, -in1) + (in0, in1, in2), 0) = (in0-valid, in1-in0, in2-in1)
    float3 blend = max(float3(inside.x - specialValidF, inside.y - inside.x, inside.z - inside.y), 0.0);
    float4 shadowSel = float4(specialValidF, invValidity * blend.x, invValidity * blend.y, invValidity * blend.z);
    float weightedSum = dot(shadowSel, float4(1.0, 4.0, 3.0, 2.0));
    float toSphereShadow = clamp(dot(toSphere, float3(shadowSel.y, shadowSel.z, shadowSel.w)) * 4.0 - 3.0, 0.0, 1.0);
    float cascadeF = clamp(4.0 - weightedSum, 0.0, 3.0);
    uint cascadeIndex = uint(cascadeF);

    float offIndex = (cascadeIndex == 0u) ? (tooFar ? inside.y : 0.0)
                   : (cascadeIndex == 1u) ? outClip.x
                   : (cascadeIndex == 2u) ? outClip.y
                   : outClip.z;

    float finalCascadeF = cascadeF;
    if (useDither)
    {
        float2 pixelCoord = uv * _LianCascadeMaskSize;
        int2 px = int2(pixelCoord);
        int ditherIndex = ((px.y & 3) << 2) | (px.x & 3);
        bool shouldDiscard = toSphereShadow >= _LianCascadeDither[ditherIndex];
        finalCascadeF = clamp(cascadeF + (shouldDiscard ? offIndex : 0.0), 0.0, 3.0);
    }
    uint finalCascade = uint(finalCascadeF);

    // ---- worldToShadow(行序)----
    int rowBase = int(finalCascade) << 2;
    float3 shadowCS = _LianWorldToShadow[rowBase + 0].xyz * scaledDir.x
                    + _LianWorldToShadow[rowBase + 1].xyz * scaledDir.y
                    + _LianWorldToShadow[rowBase + 2].xyz * scaledDir.z
                    + _LianWorldToShadow[rowBase + 3].xyz;

    // ---- 5×5 手动 PCF(dump 6 组 gather + frac 加权)----
    float2 shadowUV = shadowCS.xy * _LianShadowMapTexel.zw + (-0.5);
    float shadowDepth = min(shadowCS.z, 1.0);
    float2 fracUV = frac(shadowUV);
    float2 oneMinusFrac = 1.0 - fracUV;
    float2 center = floor(shadowUV) * _LianShadowMapTexel.xx + (_LianShadowMapTexel.x * 0.5);
    float2 texel = _LianShadowMapTexel.xx;
    float slice = float(finalCascade);
    // 反向 Z:lit ⟺ atlas ≤ shadowDepth(含等号,自阴影由 _ShadowBias 分离);
    // Tuanjie 解析器不支持方法调用作 step 首参,先取临时变量
    float4 b1G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(2.0, -2.0) * texel, slice));
    float4 b1 = step(b1G, shadowDepth);
    float4 b0G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(2.0, 0.0) * texel, slice));
    float4 b0 = step(b0G, shadowDepth);
    float4 b2G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(-2.0, -2.0) * texel, slice));
    float4 b2 = step(b2G, shadowDepth);
    float4 b3G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(0.0, -2.0) * texel, slice));
    float4 b3 = step(b3G, shadowDepth);

    float2 acc = float2(b2.w * oneMinusFrac.x + b2.z, b2.x * oneMinusFrac.x + b2.y);
    acc += float2(b3.w, b3.x);
    acc += float2(b3.z, b3.y);
    acc += float2(b1.w, b1.x);
    acc += float2(b1.z * fracUV.x, b1.y * fracUV.x);
    float sum = acc.x * oneMinusFrac.y + acc.y;

    float4 c0G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center, slice));
    float4 c0 = step(c0G, shadowDepth);
    float4 c1G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(-2.0, 0.0) * texel, slice));
    float4 c1 = step(c1G, shadowDepth);
    acc = float2(c1.w * oneMinusFrac.x + c1.z, c1.x * oneMinusFrac.x + c1.y);
    acc += float2(c0.w, c0.x);
    acc += float2(c0.z, c0.y);
    acc += float2(b0.w, b0.x);
    acc += float2(b0.z * fracUV.x, b0.y * fracUV.x);
    sum += acc.x + acc.y;

    float4 d0G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(2.0, 2.0) * texel, slice));
    float4 d0 = step(d0G, shadowDepth);
    float4 d1G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(-2.0, 2.0) * texel, slice));
    float4 d1 = step(d1G, shadowDepth);
    float4 d2G = _LianShadowAtlasTex.Gather(sampler_LianShadowAtlasTex, float3(center + float2(0.0, 2.0) * texel, slice));
    float4 d2 = step(d2G, shadowDepth);
    acc = float2(d1.w * oneMinusFrac.x + d1.z, d1.x * oneMinusFrac.x + d1.y);
    acc += float2(d2.w, d2.x);
    acc += float2(d2.z, d2.y);
    acc += float2(d0.w, d0.x);
    acc += float2(d0.z * fracUV.x, d0.y * fracUV.x);
    sum += acc.x + acc.y * fracUV.y;

    float shadow = sum * 0.039999999105930328369140625;
    return shadow * shadow;
}

#endif // LIAN_CASCADE_SAMPLE_INCLUDED
