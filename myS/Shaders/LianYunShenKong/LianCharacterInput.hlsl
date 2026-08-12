#ifndef LIAN_CHARACTER_INPUT_INCLUDED
#define LIAN_CHARACTER_INPUT_INCLUDED

// LianCharacter.shader 材质参数与管线全局(dump `_9`/`_14`/`_21`/`_24`/`_27`/`_37` 各块)。
// 命名规则见计划:dump 注释语义 / URP 等价内置 / 数据流推导。
// 本 fork 的 Properties 自动声明对部分属性不可靠(随编译顺序变化),材质属性一律显式声明为普通全局;
// 帧级全局(非属性)单独 CBUFFER。

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// ---------------- 纹理 ----------------
TEXTURE2D(_BaseMap);         SAMPLER(sampler_BaseMap);          // dump `_46` diffuse/albedo
TEXTURE2D(_ParamMap);        SAMPLER(sampler_ParamMap);         // dump `_47` xz = metallic/roughness
TEXTURE2D(_NormalMap);       SAMPLER(sampler_NormalMap);        // dump `_48`
TEXTURE2D(_DetailNormalMap); SAMPLER(sampler_DetailNormalMap);  // dump `_49`
TEXTURE2D(_TintMask);        SAMPLER(sampler_TintMask);         // dump `_50` 脸红/耳朵红
TEXTURE2D(_DecalTex);        SAMPLER(sampler_DecalTex);         // dump `_51`
TEXTURE2D(_DetailTex);       SAMPLER(sampler_DetailTex);        // dump `_52`(texcoord1)
TEXTURECUBE(_EnvCube);       SAMPLER(sampler_EnvCube);          // dump `_41` 环境立方体贴图
TEXTURE3D(_FogLUT3D);        SAMPLER(sampler_FogLUT3D);         // dump `_55` 雾 LUT

// ---------------- 管线 RT(全局绑定) ----------------
TEXTURE2D_X(_LianShadowAOTex);          SAMPLER(sampler_LianShadowAOTex);          // r=shadow g=soft a=AO
TEXTURE2D_X(_LianSSSTex);               SAMPLER(sampler_LianSSSTex);               // SSS 光照
TEXTURE2D_X(_LianTileLightIndexTex);    SAMPLER(sampler_LianTileLightIndexTex);    // 世界 XZ tile 灯光索引

// ---------------- 灯光数组(dump `_9`) ----------------
StructuredBuffer<float4> _LianLightPosType;     // _9._m0[20]
StructuredBuffer<float4> _LianLightSpotAtten;   // _9._m1[20]
StructuredBuffer<float4> _LianLightColor;       // _9._m3[20]
StructuredBuffer<float4> _LianLightDistAtten;   // _9._m4[20]
StructuredBuffer<float4> _LianLightSpotDir;     // _9._m5[20]
StructuredBuffer<float4> _LianLightShadowSel;   // _9._m6[20]

// ---------------- 材质属性(显式声明;与 LianCharacter.shader Properties 对应) ----------------
float4 _SkyLightDir;          // _24._m0.xyz 天空光方向
float  _BakedGIBlend;         // _24._m0.w
float4 _BakedGIOffset;        // _24._m1.xyz
float  _GILerp;               // _24._m1.w
// _MainLightColor 由 Properties 自动声明(实测显式声明会 redefinition)
float4 _SkyLightColor;        // _24._m3.xyz
float  _HeightOffset;         // _24._m4.y
float  _AlphaScale;           // _24._m4.w
float  _BakedGIStrength;      // _24._m5
float  _ShadowStrength;       // _24._m6
float  _HeightFactor;         // _24._m7
float  _NormalSelectRight;    // _24._m13
float  _NormalSelectLeft;     // _24._m14
float4 _ColorTint;            // _27._m1.xyz
float4 _AlbedoMColor;         // _27._m2.xyz
float4 _DecalColor;           // _27._m4
float4 _TintControlBase;      // _27._m7.xyz
float4 _TintMaskWeights;      // _27._m8
float  _BrightM;              // _27._m11
float  _Specular;             // _27._m12
float  _AlbedoMMix;           // _27._m15
float  _OutputAlpha;          // _27._m18
float  _EnvIntensity;         // _21._m4.x
float  _EnvPower;             // _21._m4.y
float  _EnvAlphaLerp;         // _21._m4.w
float4 _FogWindDirA;          // _37._m0
float  _FogLUTDepthScale;     // _37._m1
float4 _FogDirInscatColor;    // _37._m6
float  _FogDirStartDist;      // _37._m7
float4 _FogStartDist;         // _37._m8.x
float4 _FogDensity;           // _37._m9
float4 _FogVolumetricAlbedo;  // _37._m10.xyz
float  _FogBlendOffset;       // _37._m12
float  _FogBlendScale;        // _37._m13
float4 _FogVolumeOrigin;      // _37._m14

// ---------------- 帧级全局(非材质属性,每帧由 pass 设置) ----------------
CBUFFER_START(LianFrameGlobals)
    float3 _MainLightDir;         // _14._m1.xyz 主光方向
    float4 _LianTileGridParams;   // _14._m4: xy=网格原点, zw=tile 世界尺寸
    float  _AlphaMix;             // _14._m6: 输出 alpha 混合系数
    float  _TextureMipBias;       // _14._m7: 贴图 mip bias
CBUFFER_END

#endif // LIAN_CHARACTER_INPUT_INCLUDED
