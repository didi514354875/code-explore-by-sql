#ifndef LIAN_SHARED_INCLUDED
#define LIAN_SHARED_INCLUDED

// 恋与深空管线共享工具:法线球面编码/解码、MV 打包/解包、噪声、Bayer。
// 使用前需先 include URP Core.hlsl。SH9 求值见 LianCharacterGI.hlsl
// (依赖 URP BRDF/GlobalIllumination 包含顺序,全屏 shader 不需要)。
// 全部公式逐位对照 dump(lianyushengkong.shader),行号见各函数注释。

// ---------------------------------------------------------------
// 2×2 Bayer 抖动偏移表(dump 线 399)
// const float _191[4] = float[](-0.01171875, 0.00390625, 0.01171875, -0.00390625);
// 索引 = ((uint(fragCoord.x) & 1) << 1) | (uint(fragCoord.y) & 1)
// ---------------------------------------------------------------
static const float LianBayer2x2[4] = { -0.01171875, 0.00390625, 0.01171875, -0.00390625 };

float LianBayer2x2Value(float2 pixelPos)
{
    uint idx = ((uint(pixelPos.x) & 1u) << 1u) | (uint(pixelPos.y) & 1u);
    return LianBayer2x2[idx];
}

// ---------------------------------------------------------------
// 法线球面映射编码(dump `_43`,线 460-469)
// z 通道存 0.495(z<0)/0.505(z≥0) 区分正反面
// ---------------------------------------------------------------
float3 LianEncodeNormalSpheremap(float3 n)
{
    float zCh = (n.z < 0.0) ? 0.49500000476837158203125 : 0.50499999523162841796875;
    float denom = abs(n.z) + 1.0;
    float2 xy = n.xy / denom;           // [-1,1]
    return float3(xy * 0.5 + 0.5, zCh); // [0,1]
}

// 法线球面映射解码(dump `_69`,线 1840-1855)
float3 LianDecodeNormalSpheremap(float3 enc)
{
    float2 n01 = enc.xy * 2.0 - 1.0;
    float signF = (enc.z * 2.0 - 1.0) > 0.0 ? 1.0 : -1.0;   // 0.505→+1, 0.495→-1
    float lenSq = dot(n01, n01);
    float denom = 1.0 + lenSq;
    float3 n;
    n.xy = (n01 * 2.0) / denom;
    n.z = signF * (1.0 - lenSq) / denom;
    return n;
}

// ---------------------------------------------------------------
// 运动矢量打包(dump 线 442-455):输入 NDC 空间运动 [-2,2] 内的差值,
// 输出 float4:(highX, lowX, highY, lowY) 各 /255(高8位在前)。
// ---------------------------------------------------------------
float4 LianEncodeMotionVector(float2 motionNDC)
{
    float2 v = motionNDC * 0.2495000064373016357421875 + 0.49999237060546875;
    float2 scaled = v * 65535.0;
    uint2 u = uint2(scaled);            // 截断
    uint2 high = u >> 8u;
    uint2 low = u & 0xFFu;
    return float4(high.x, low.x, high.y, low.y) / 255.0;
}

// 运动矢量解包(dump `_88`,线 3842-3860)
// roundEven(半值向偶)非所有编译器内置,本地实现(输入 ≥ 0 的量化值)
float4 LianRoundEven(float4 x)
{
    float4 r = round(x);
    float4 halfMask = (abs(frac(x) - 0.5) < 1e-6) ? 1.0 : 0.0;
    float4 oddMask = (abs(frac(r * 0.5) - 0.5) < 1e-6) ? 1.0 : 0.0;
    return r - halfMask * oddMask;
}

float2 LianDecodeMotionVector(float4 encoded)
{
    float4 v = LianRoundEven(encoded * 255.0);
    uint4 u = uint4(v);
    uint2 combined = uint2(u.y + (u.x << 8u), u.w + (u.z << 8u));
    return float2(combined) * 6.1158403696026653051376342773438e-05 + (-2.0039775371551513671875);
}

// ---------------------------------------------------------------
// 快速哈希(dump soft shadow pass,线 2083-2100):pixelPos / 2048 的
// 带符号 frac + 两轮 3571 hash。返回 [0,1]。
// ---------------------------------------------------------------
float LianRandFast(float2 pixelPos)
{
    float2 hashSeed = pixelPos / 2048.0;
    // 带符号 frac:dump 的 signMask 三元 = frac(|v|)·sign(v)(v=0 时两者均为 0,逐位一致)
    hashSeed = frac(abs(hashSeed)) * sign(hashSeed);
    hashSeed = hashSeed * 0.474074065685272216796875 + float2(0.25, 0.0);
    hashSeed *= hashSeed;
    float h = dot(hashSeed, float2(3571.0, 3571.0));
    h = frac(h);
    h *= h;
    h = dot(float2(h, h), float2(3571.0, 3571.0));
    return frac(h);
}

#endif // LIAN_SHARED_INCLUDED
