// NPRCharacter/SkinInput.hlsl
// 皮肤材质参数 —— 对应原始 skin.shader 的 cb5/cb0 槽位(以 skin.shader asm 注释为准)。
// 槽位 → 属性表(全表即 Properties,无遗漏):
//   t8 / cb5[26].xyz  _BaseMap / _BaseColor
//   t9 / cb5[0].w     _NormalMap / _NormalScale
//   t7 / t6 / t10 / t2 / t3,4,5 / t11   _ColorGradeLUT / _RampTex / _MatCapTex / _CharacterShadowTex /
//                                       _VolumeIndex3D,_VolumeLight3D,_VolumeLightLowFreq3D / _FogLUT3D(共享声明,见 NPRCharacterInput.hlsl)
//   cb5[0].x/.y/.z    _Smoothness / _SpecularStrength / _Metallic
//   cb5[2].z / cb5[24].xyz  _RimTintStrength / _RimTintColor
//   cb5[14].w         _DoubleSidedFlip
//   cb5[19].xyz / cb0[170]  _RainAreaCenter / _RainAreaControl(x=blend y=centerX z=tiling w=centerY)
//   cb0[164].xyz / cb0[161].w  _MainLightDirOverride / _CharacterLightBlend
//   cb0[171].xyz / cb0[165].w  _MainLightColorOverride / _LightColorOverrideBlend
//       —— 注意:skin/face 的颜色覆盖在 cb0[171].xyz(cloth 在 cb0[165].xyz,以各自 asm 为准,asm 295/345)
//   cb0[160].z/.y/.w  _ShadowStrength / _LightRadianceScale / _EnvIntensity
//   cb4[30].x / cb4[31].z  _ShadowTexIntensity / _SceneShadowFallback(无阴影纹理回退值,URP 路径用实时阴影)
//   cb0[161].z / .y / .x  _SceneShadowMix / _GI_MODE / _AmbientIntensityMix
//   cb0[163].w / cb0[164].w  _BackLightControl / _BackLightBias
//   cb0[163].xyz       _SHColorConst
//   cb0[166].xyz / cb0[167].x/y/z  _SkyDir(仅 xz 用) / _SkyOffset / _SkyScale / _SkyBias
//   cb0[168] / cb0[169].xyz / cb0[167].w / cb0[166].w  _RimColor / _RimDir / _RimRange / _RimFresnelMix
//   cb1[inst+5].w      _InstanceDirSign
//   cb0[91].x / cb0[89].x / cb0[88].x  _AmbientBase / _Exposure / _MipBias
// 注:cb0[160].x(附加光阴影强度,cloth 用)在 skin/face 附加光循环无引用,不声明;
//     cb0[169].w / cb0[88].w 为引擎标志位(URP 无对应,不声明)。
#ifndef NPRCHARACTER_SKIN_INPUT_INCLUDED
#define NPRCHARACTER_SKIN_INPUT_INCLUDED

#include "NPRCharacterInput.hlsl"

// ============================================================================
// 材质参数 —— 对应原始 cb5/cb0 槽位
// ============================================================================
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;                     // cb2[51]  uv 平铺偏移
    float4 _BaseColor;                      // cb5[26]  基础色染色
    float4 _MainLightDirOverride;           // cb0[164].xyz 角色主光方向覆盖(指向光源方向)
    float4 _MainLightColorOverride;         // cb0[171].xyz 主光颜色覆盖(skin/face 槽位,asm 295)
    float4 _SHColorConst;                   // cb0[163].xyz GI Const 模式颜色
    float4 _SkyDir;                         // cb0[166].xyz ndotSky 方向(asm 249 仅用 .xz)
    float4 _RimColor;                       // cb0[168] 边缘光颜色 + w>0.01 开关
    float4 _RimDir;                         // cb0[169].xyz 边缘光参考方向
    float4 _RimTintColor;                   // cb5[24].xyz 边缘染色颜色
    float4 _RainAreaCenter;                 // cb5[19].xyz 雨区域中心
    float4 _RainAreaControl;                // cb0[170] x=blend y=centerX z=tiling w=centerY
    float  _NormalScale;                    // cb5[0].w  法线强度
    float  _Smoothness;                     // cb5[0].x  粗糙度 = 1 - x(asm 275-280)
    float  _SpecularStrength;               // cb5[0].y  f0 基 = 值×0.04(asm 276/283)
    float  _Metallic;                       // cb5[0].z  (asm 281)
    float  _RimTintStrength;                // cb5[2].z  边缘染色强度(asm 256)
    float  _DoubleSided;                    // [Toggle] 双面渲染开关(驱动 _DOUBLE_SIDED 关键字)
    float  _DoubleSidedFlip;                // cb5[14].w 背面法线翻转量
    float  _CharacterLightBlend;            // cb0[161].w 主光方向覆盖混合
    float  _LightColorOverrideBlend;        // cb0[165].w 颜色覆盖混合
    float  _BackLightControl;               // cb0[163].w 背光补偿强度(1=关)
    float  _BackLightBias;                  // cb0[164].w 背光 ramp 偏移
    float  _ShadowStrength;                 // cb0[160].z 暗部强度
    float  _LightRadianceScale;             // cb0[160].y 光照强度
    float  _EnvIntensity;                   // cb0[160].w 环境强度
    float  _SceneShadowMix;                 // cb0[161].z 场景阴影混合(0=完全用阴影,1=忽略)
    float  _GI_MODE;                        // cb0[161].y GI 模式(驱动 _GI_MODE_* 关键字,0/1/2/3 -> Volume/Const/MatCap/URPProbe)
    float  _BakedGIStrength;                // min(cb0[161].y,1) ramp 阴影的环境衰减
    float  _MatCapMix;                      // cb0[162].w MatCap 混合
    float  _AmbientIntensityMix;            // cb0[161].x mulIntensity1 的 lerp 系数(asm 352)
    float  _AmbientBase;                    // cb0[91].x 环境光基准
    float  _SkyOffset;                      // cb0[167].x ndotSky 偏移
    float  _SkyScale;                       // cb0[167].y ndotSky 强度
    float  _SkyBias;                        // cb0[167].z ndotSky 偏置
    float  _RimRange;                       // cb0[167].w 边缘光范围
    float  _RimFresnelMix;                  // cb0[166].w rim 漫反射混合
    float  _InstanceDirSign;                // 原 cb1[inst+5].w 实例方向符号(与 tangentOS.w 求符号积)
    float  _ShadowTexIntensity;             // cb4[30].x 屏幕空间阴影强度
    float  _SceneShadowFallback;            // cb4[31].z 无阴影纹理时回退值(原始引擎标志位 cb4[31].x 已由关键字 _SCENE_SHADOW_TEX 取代)
    float  _Exposure;                       // cb0[89].x 输出曝光
    float  _MipBias;                        // cb0[88].x 全局 mip bias(整型位 cb0[88].w 供雾 LUT hash 使用)
    float  _Cull;                           // 双面渲染时的 Cull 状态(0=Off, 2=Back;由 _DOUBLE_SIDED 关键字决定,C# 同步)
CBUFFER_END

// ============================================================================
// 纹理(皮肤特有;共享槽位见 NPRCharacterInput.hlsl)
// ============================================================================
TEXTURE2D(_BaseMap);            // t8  基础色
TEXTURE2D(_NormalMap);          // t9  法线贴图

#endif // NPRCHARACTER_SKIN_INPUT_INCLUDED
