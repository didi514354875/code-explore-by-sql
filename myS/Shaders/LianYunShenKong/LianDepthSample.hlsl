// LianDepthSample.hlsl — 相机深度采样统一点采样。
// 深度拷贝 RT 为 R32_SFloat,D3D11 上线性过滤(默认 sampler 状态)不可用 → 返回 0;
// 点采样与 URP Blit FragNearest 一致,返回原始深度。
// 使用前提:已 include DeclareDepthTexture.hlsl(声明 _CameraDepthTexture)与 Blit.hlsl
// (声明 sampler_PointClamp)。
#ifndef LIAN_DEPTH_SAMPLE_INCLUDED
#define LIAN_DEPTH_SAMPLE_INCLUDED

float LianSampleSceneDepth(float2 uv)
{
    return _CameraDepthTexture.Sample(sampler_PointClamp, uv).r;
}

#endif
