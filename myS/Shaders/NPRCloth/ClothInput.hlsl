// NPRCloth/ClothInput.hlsl
// 明日方舟终末地风格卡通布料 —— 材质参数与全局常量(与原始 cloth.shader 的 cb0/cb1/cb4/cb5 槽位一一对应,见各字段注释)
// 所有可调参数进入 UnityPerMaterial CBUFFER 以保证 SRP Batcher 兼容;帧级/体积 GI/雾参数为全局 CBUFFER(C# 每帧设置)。
#ifndef NPRCLOTH_CLOTH_INPUT_INCLUDED
#define NPRCLOTH_CLOTH_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"  // LerpWhiteTo(Shadows.hlsl:309 需要)
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

// ============================================================================
// 通用颜色工具(供所有模块使用)
// ============================================================================

// 亮度(asm 权重 0.2127/0.7152/0.0722,与 Unity Luminance 略有差异,以 asm 为准)
float ClothLuminance(float3 c)
{
    return dot(c, float3(0.2127, 0.7152, 0.0722));
}

// AdjustSaturation(c, s) = lerp(Luminance(c), c, s)(asm 4-7)
float3 AdjustSaturationCloth(float3 c, float s)
{
    float lum = ClothLuminance(c);
    return lerp(lum, c, s);
}

// ============================================================================
// 材质参数 —— 对应原始 cb5/cb0 槽位
// ============================================================================
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;                     // cb2[51]  uv 平铺偏移
    float4 _BaseColor;                      // cb5[26]  基础色染色
    float4 _MainLightDirOverride;           // cb0[164].xyz 角色主光方向覆盖(指向光源方向)
    float4 _MainLightColorOverride;         // cb0[165].xyz 主光颜色覆盖
    float4 _SHColorConst;                   // cb0[162].xyz GI Const 模式颜色
    float4 _SkyDir;                         // cb0[166].xyz ndotSky 方向
    float4 _RimColor;                       // cb0[168] 边缘光颜色 + w>0.01 开关
    float4 _RimDir;                         // cb0[169].xyz 边缘光参考方向
    float4 _RainAreaCenter;                 // cb5[19].xyz 雨区域中心
    float4 _RainAreaControl;                // cb0[170] x=blend y=centerX z=tiling w=centerY
    float  _NormalScale;                    // cb5[0].w  法线强度
    float  _ShadowColorIntensity;           // cb5[5].y  阴影色强度
    float  _ShadowColorSaturation;          // cb5[5].z  阴影色饱和度
    float  _SpecStylizedStrength;           // cb5[2].y  风格化高光强度
    float  _AlphaMode;                      // cb5[7].x  1=输出 baseColor.a
    float  _BaseAlphaInfluence;             // cb5[9].w  合成时 baseColor.a 影响
    float  _DoubleSided;                    // [Toggle] 双面渲染开关(驱动 _DOUBLE_SIDED 关键字)
    float  _DoubleSidedFlip;                // cb5[14].w 背面法线翻转量
    float  _CharacterLightBlend;            // cb0[161].w 主光方向覆盖混合
    float  _LightColorOverrideBlend;        // cb0[165].w 颜色覆盖混合
    float  _BackLightControl;               // cb0[163].w 背光补偿强度(1=关)
    float  _BackLightBias;                  // cb0[164].w 背光 ramp 偏移
    float  _ShadowStrength;                 // cb0[160].z 暗部强度
    float  _LightRadianceScale;             // cb0[160].y 光照强度
    float  _EnvIntensity;                   // cb0[160].w 环境强度
    float  _AdditionalShadowScale;          // cb0[160].x 附加光阴影强度(URP 路径:附加光阴影由 light.shadowAttenuation 提供)
    float  _SceneShadowMix;                 // cb0[161].z 场景阴影混合(0=完全用阴影,1=忽略)
    float  _GI_MODE;                        // cb0[161].y GI 模式(驱动 _GI_MODE_* 关键字,0/1/2/3 -> Volume/Const/MatCap/URPProbe)
    float  _BakedGIStrength;                // min(cb0[161].y,1) ramp 阴影的环境衰减
    float  _MatCapMix;                      // cb0[162].w MatCap 混合
    float  _AmbientBase;                    // cb0[91].x 环境光基准(forward 恒 1,保留)
    float  _SkyOffset;                      // cb0[167].x ndotSky 偏移
    float  _SkyScale;                       // cb0[167].y ndotSky 强度
    float  _SkyBias;                        // cb0[167].z ndotSky 偏置
    float  _RimRange;                       // cb0[167].w 边缘光范围
    float  _RimFresnelMix;                  // cb0[166].w rim 漫反射混合
    float  _RainFlowSpeed;                  // cb0[82].x 替代(_Time.y 驱动的水流速度)
    float  _FlipRainY;                      // 原 cb1[inst+4].w 雨 UV Y 翻转
    float  _InstanceDirSign;                // 原 cb1[inst+5].w 实例方向符号(与 tangentOS.w 求符号积)
    float  _ShadowTexIntensity;             // cb4[30].x 屏幕空间阴影强度
    float  _SceneShadowFallback;            // cb4[31].z 无阴影纹理时回退值(原始引擎标志位 cb4[31].x 已由关键字 _SCENE_SHADOW_TEX 取代)
    float  _Exposure;                       // cb0[89].x 输出曝光
    float  _MipBias;                        // cb0[88].x 全局 mip bias(整型位 cb0[88].w 供雾 LUT hash 使用)
    float  _Cull;                           // 双面渲染时的 Cull 状态(0=Off, 2=Back;由 _DOUBLE_SIDED 关键字决定,C# 同步)
CBUFFER_END

// ============================================================================
// 纹理(采样器统一使用 Core 内置全局采样器:基础/法线/雨/水流 Repeat,其余 Clamp)
// ============================================================================
TEXTURE2D(_BaseMap);            // t10 基础色
TEXTURE2D(_PBRParamTex);        // t11 R=金属 G=高光系数 B=AO A=光滑度
TEXTURE2D(_NormalMap);          // t12 法线贴图
TEXTURE2D(_RampTex);            // t6  漫反射 ramp
TEXTURE2D(_SpecStylizedLUT);    // t7  风格化高光 LUT
TEXTURE2D(_RainDropTex);        // t8  水点控制(法线等)
TEXTURE2D(_RainFlowTex);        // t9  水流控制
TEXTURE2D(_MatCapTex);          // t14 MatCap
TEXTURE2D(_CharacterShadowTex); // t2  屏幕空间阴影 r=场景阴影 g=角色自阴影
TEXTURE3D(_VolumeIndex3D);      // t3  体积 GI 索引
TEXTURE3D(_VolumeLight3D);      // t4  体积 GI 光照
TEXTURE3D(_VolumeLightLowFreq3D);// t5  体积 GI 低频
TEXTURE3D(_FogLUT3D);           // t15 雾 LUT

// ============================================================================
// 帧级全局(C# ClothFrameData 每帧设置,不属材质)
// _NonJitteredVP 对应原始 cb0[24..27];_PrevViewProjMatrix 直接使用 URP 已声明的全局
// (UnityInput.hlsl:274,非抖动运动矢量矩阵),不再重复声明。
// ============================================================================
CBUFFER_START(ClothPerFrame)
    float4x4 _NonJitteredVP;        // 原 cb0[24..27] 非抖动视图投影矩阵
CBUFFER_END

// ============================================================================
// 体积 GI 全局(C# 侧 ClothVolumeBinder 填,本实现默认 URPProbe 模式不填)
// ============================================================================
CBUFFER_START(ClothVolumeGI)
    float4 _VolumeOrigin;       // cb0[175].xyz 体积原点
    float  _VolumeHasIndex;     // cb0[175].w 是否有索引贴图(>0 采样)
    float4 _VolumeResolution;   // cb0[176] 索引贴图分辨率(倒数)
    float4 _VolumeSH0;          // cb0[178] 渐变目标 SH0
    float4 _VolumeSH1;          // cb0[179] 渐变目标 SH1
    float4 _VolumeSH2;          // cb0[180] 渐变目标 SH2
CBUFFER_END

// ============================================================================
// 雾全局(C# ClothFogVolume 设置,不属材质)
// ============================================================================
CBUFFER_START(ClothFog)
    float  _FogDensity;             // cb0[136].w
    float  _FogStartDistance;       // cb0[134].w
    float  _FogStartHeight;         // cb0[133].w
    float  _FogEndHeight;           // cb0[135].w
    float  _FogHeightFalloff;       // cb0[131].w
    float4 _FogLightDir;            // cb0[136].xyz 散射参考光方向
    float4 _FogBaseColor;           // cb0[133].xyz 基础雾色
    float4 _FogScatteringScale;     // cb0[131].xyz 散射强度
    float4 _FogRayleighColor;       // cb0[134].xyz Rayleigh 色
    float4 _FogMieColor;            // cb0[132].xyz Mie 色
    float4 _FogMieG;                // cb0[132].w Mie 相位常数 g
    float4 _FogFinalColorScale;     // cb0[135].xyz 最终雾色缩放
    float4 _FogLUTParams0;          // cb0[137] 相机高度带指数参数(x=相机高度基准, y=强度, z=高度衰减率)
    float4 _FogLUTParams1;          // cb0[138] 距离积分参数(x,y = 近端区间, z,w = 远端区间)
    float4 _FogLUTParams2;          // cb0[139] xyz=雾颜色, w=雾因子下限
    float4 _FogLUTParams3;          // cb0[140] 第二高度带指数参数(x,y,z 同上, y>0 启用)
    float4 _FogLUTParams4;          // cb0[141] z=log 归一化除数(>0 启用 LUT), w=1/forwardFactor 强度
    float4 _FogLUTParams5;          // cb0[142] xyz=log 变换 (posCS.w*x+y 取 log 再乘 z)
    float4 _FogLUTParams6;          // cb0[143] xy=uv 缩放
    float4 _FogLUTParams7;          // cb0[144] z=解析/LUT 混合阈值距离
    float4 _FogLUTParams8;          // cb0[145] w=hash 抖动强度
CBUFFER_END

// ============================================================================
// 附加光源风格化参数(原 cb3[light*64+6..62] 槽位 1:1;由 StylizedLightRenderFeature 填充)
// ============================================================================
struct ClothStylizedLightData
{
    float4 colorAndType;         // 原 cb3[light*64+6]  rgb 颜色(含强度) w 类型(0点光 1聚光, >=2 跳过)
    float4 positionAndInvRadius; // 原 cb3[light*64+14] xyz 位置 w 1/range
    float4 tangentAndCapsule;    // 原 cb3[light*64+16] x,y 半八面体切线打包值 w 胶囊长度(0=非胶囊) z 预留(0)
    float4 modeParams0;          // 原 cb3[light*64+24] xyz=(cosInner, cosOuter, 1/(cosInner-cosOuter)) w=renderMode(0-4)
    float4 modeParams1;          // 原 cb3[light*64+32] 按模式复用(见 ApplyAdditionalLights)
    float4 tangentWS;            // 原 cb3[light*64+46] 全精度切线世界方向(f16 解包删除)
    float4 spotDirWS;            // 原 cb3[light*64+54] xyz 聚光方向(全精度) w 非mode4衰减指数
    float4 specularParams;       // 原 cb3[light*64+62] z=高光强度
};

StructuredBuffer<ClothStylizedLightData> _StylizedLightParamsBuffer;

// ============================================================================
// 材质解码结果(Step 3):与 asm PS 0-53 的寄存器一一对应
// ============================================================================
struct ClothSurfaceData
{
    float3 baseColor;            // 基础色(雨修正后)
    float  baseAlpha;            // 基础色 alpha(asm r0.w)
    float  metallic;             // pbr.r
    float  specularScale;        // pbr.g
    float  ao;                   // pbr.b
    float  roughness;            // 1 - pbr.a(雨修正后)
    float3 shadowBaseColor;      // AdjustSaturation(baseColor * _ShadowColorIntensity, _ShadowColorSaturation)(雨修正后)
    float3 diffuseColor;         // (0.96 - 0.96*metallic) * baseColor
    float3 specularColor;        // lerp(specularScale*0.04, baseColor, metallic)
    float3 shadowDiffuseColor;   // (0.96 - 0.96*metallic) * shadowBaseColor
    float  roughnessSqr;         // max(roughness^2, 0.0078)
    float  roughnessSqrSqr;      // roughnessSqr^2
    float3 normalTWS;            // 切线空间法线(翻转后)
    float3 normalWS;             // 几何法线(翻转后,附加光用)
    float  wetFactor;            // 雨湿润因子(0=干)
    float  wetRoughness;         // 湿润粗糙度(干=0.01)
};

#endif // NPRCLOTH_CLOTH_INPUT_INCLUDED
