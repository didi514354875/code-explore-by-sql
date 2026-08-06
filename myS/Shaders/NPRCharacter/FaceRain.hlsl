// NPRCharacter/FaceRain.hlsl
// 脸部雨湿润(face asm 260-330;与 cloth 雨 252-386 同源,但 face 特例:
//   - 雨 uv 用 v0.xy + y 方向 frac 偏移的 uv 采样(asm 276-283),无 positionOS 采样、无 _FlipRainY
//   - dropControl 自 _RainDropTex(t8),flowW2 为 _RainDropTex.w,遮罩 _RainFlowTex(t9) 的 z 通道
//   - wetRoughness 湿时固定 0.3(asm 325)
//   - baseAlpha 乘湿润暗化(asm 324)
// 动态分支 if (rainOn > 0.0001)(asm 259-260),不建关键字。
#ifndef NPRCHARACTER_FACE_RAIN_INCLUDED
#define NPRCHARACTER_FACE_RAIN_INCLUDED

#include "NPRCharacterInput.hlsl"
#include "NPRCharacterVertex.hlsl"

// 雨湿润处理(face asm 260-330):修改 baseAlpha/specularStrength/roughness/normalTWS(wetNormal),输出 wetFactor/wetRoughness
void GetFaceRain(CharacterVaryings input, float faceFlip, float specularBase, float dotD, float rainOn, inout CharacterSurfaceData surface)
{
    if (rainOn > 0.0001)
    {
        // asm 261-274: 切线基(与皮肤 TBN 相同,按 asm 顺序在雨分支内计算)
        float invLen = rsqrt(max(dot(input.normalWS, input.normalWS), 1e-6));
        float3 tNormal = input.normalWS * invLen;
        float3 tTangent = input.tangentWS.xyz * invLen;
        float3 tBitangent = cross(input.normalWS, input.tangentWS.xyz) * input.tangentWS.w * invLen;

        // asm 276-283: 雨 uv(仅 v0.xy + y 方向 frac 偏移)
        float2 uv1 = input.uv + float2(0.0, frac(_RainFlowSpeed * 0.8));
        float2 uv2 = input.uv + float2(0.0, frac(_RainFlowSpeed * 0.8 + 0.005));
        float4 dropControl = SAMPLE_TEXTURE2D_BIAS(_RainDropTex, sampler_LinearRepeat, uv1, _MipBias);  // asm 280
        float flowW2 = SAMPLE_TEXTURE2D_BIAS(_RainDropTex, sampler_LinearRepeat, uv2, _MipBias).w;       // asm 284(t8.wxyz → texel.w)
        float fmask = SAMPLE_TEXTURE2D_BIAS(_RainFlowTex, sampler_LinearRepeat, input.uv, _MipBias).z;   // asm 285(t9.xywz → texel.z,以指令为准)

        // asm 286-304: 湿润因子
        float dropW = dropControl.w;                                   // r15.y(286)
        float flowW1 = fmask * flowW2;                                 // r15.y(287)
        float dropFlowW = fmask * dropW;                               // r15.z(287)
        float dropMask = fmask * dropControl.z;                        // r7.w(288)
        float2 flowN = dropControl.xy * 2.0 - 1.0;                     // 289
        float wetBlend = saturate(dropFlowW + flowW1);                 // 290: saturate(fmask*(dropW+flowW2))
        float wetDotD = dotD * wetBlend;                               // 291
        float dropDotD = dotD * dropMask;                              // 292
        float flowNZ = sqrt(max(1.0 - saturate(dot(flowN, flowN)), 0.0));   // 293-297
        float flowYFactor = smoothstep(0.0, 1.0, saturate((flowN.y * 0.5 + 0.5) * 1.25));  // 298-302
        float flowDiff = saturate(fmask * (flowW2 - dropW));           // 303
        float wetFactor = saturate(wetDotD + dropDotD);                // 304(r15.x)

        // asm 305-312: 湿润暗化系数(1 → 0.8 → 0.9(faceControl.y 边缘固定) → wetDotD 混合)
        float wetControl = lerp(flowYFactor, 1.0, flowDiff);           // 305-306
        wetControl = lerp(1.0, 0.8, wetControl);                       // 307-308
        wetControl = lerp(wetControl, 0.9, surface.faceControl.y);     // 309-310
        float wetDarken = lerp(1.0, wetControl, wetDotD);              // 311-312

        // asm 313-319: 水点法线世界空间(含 faceFlip)
        float3 flowNWS = normalize(tTangent * flowN.x + tBitangent * flowN.y + tNormal * flowNZ) * faceFlip;

        // asm 320-323: specularStrength = lerp(fc.y*_SpecularStrength, 3, saturate(wetDotD*2+dropDotD)*dotD)
        float wetBlend2 = saturate(wetDotD * 2.0 + dropDotD) * dotD;   // 320-321
        float specularStrength = lerp(specularBase, 3.0, wetBlend2);   // 322-323

        // asm 324-325
        surface.baseAlpha *= wetDarken;                                // 324
        surface.wetFactor = wetFactor;
        surface.wetRoughness = 0.3;                                    // 325
        surface.wetNormal = flowNWS;
        surface.specularStrength = specularStrength;
    }
    else
    {
        // asm 327-329: 法线不变、wetFactor=0、wetRoughness=1-_Smoothness
        surface.wetRoughness = 1.0 - _Smoothness;
        surface.wetFactor = 0.0;
        surface.wetNormal = surface.normalTWS;
        surface.specularStrength = specularBase;
    }
}

#endif // NPRCHARACTER_FACE_RAIN_INCLUDED
