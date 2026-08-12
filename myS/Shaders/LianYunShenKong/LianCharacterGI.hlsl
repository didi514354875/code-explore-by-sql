#ifndef LIAN_CHARACTER_GI_INCLUDED
#define LIAN_CHARACTER_GI_INCLUDED

// 角色环境光:URP SHEvalLinearL0L1 + SHEvalLinearL2 封装(LianSampleSH9,见 LianShared.hlsl)。
// dump skin/render pass 的 7 次点积 SH 求值与 URP 布局逐位一致(计划复用清单)。
// 注意包含顺序:BRDF.hlsl 必须先于 GlobalIllumination.hlsl(其内引用 BRDFData)。

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "LianShared.hlsl"

// 与 dump `SampleSH9` 输出一致(负值钳 0)
half3 LianCharacterBakedGI(half3 normalWS)
{
    half3 res = SHEvalLinearL0L1(normalWS, unity_SHAr, unity_SHAg, unity_SHAb);
    res += SHEvalLinearL2(normalWS, unity_SHBr, unity_SHBg, unity_SHBb, unity_SHC);
    return max(half3(0.0, 0.0, 0.0), res);
}

#endif // LIAN_CHARACTER_GI_INCLUDED
