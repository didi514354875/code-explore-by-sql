// ShaolvQianxian2/ShaolvInput.hlsl
// 少女前线2 追放 角色 shader(原始 shaolvqianxian2.shader vs_4_0/ps_4_0 asm)的 URP 14.2.0-t1 复刻。
// 寄存器槽位一一对应:cb2 = 材质参数(UnityPerMaterial)、cb0 = 帧级全局(URP 内置优先)、cb1 = 实例数据(材质参数化)。
// 与 URP 内置一致的全局直接使用内置:_MainLightPosition/_MainLightColor(主光方向/颜色,原 cb0[7]/cb0[8])、
// _MainLightWorldToShadow(级联矩阵,原 cb0[1400+i*4..1403])、_CascadeShadowSplitSpheres0-3(级联球,原 cb0[1420..1424])、
// _MainLightShadowmapSize(原 cb0[1430])、_MainLightShadowParams(原 cb0[1429])、_Time(原 cb0[1290].y)、
// _WorldSpaceCameraPos(原 cb0[1295])、_ScreenParams(原 cb0[6].xy)、unity_SpecCube0(原 t0)、
// unity_SHAr..SHC(SH 系数,原 cb1[17..23],按 asm 布局重排)等。
#ifndef SHAOLV_INPUT_INCLUDED
#define SHAOLV_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"  // LerpWhiteTo(Shadows.hlsl:309 需要)
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// ============================================================================
// 材质参数 —— 原始 cb2 槽位(cb2[27] 为功能开关)
// ============================================================================
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;                 // cb2[0]  uv 平铺偏移(PS 内变换)
    float4 _BaseColor;                  // cb2[9]  基础色染色(仅 rgb 使用)
    float4 _TintColor;                  // cb2[10] 最终染色
    float  _DecalStrength;              // cb2[14].x 贴花强度:baseCol * _DecalStrength * pbr.a
    float  _ShadowOffset;               // cb2[15].y 级联阴影位置沿主光方向偏移量
    float  _TimeTintEnabled;            // cb2[15].z > 0.99 时启用时间变色(v7.w 噪声标志)
    float4 _TimeTintColor;              // cb2[16] xyz 时间变色目标色, w 强度
    float  _CascadeShadowOn;            // cb2[27].x > 0 启用级联阴影位置偏移
    float  _ToonOn;                     // cb2[27].y > 0 启用卡通渲染(ramp 采样)
    float  _SHDetailRemoval;            // cb2[27].w > 0 启用球谐细节去除
    float  _TangentSign;                // cb1[9].w  切线符号(与 tangentOS.w 相乘)
    float  _MaxAdditionalLights;        // cb1[10].y 附加光数量上限(min(_AdditionalLightsCount.x, 此值))
    float  _ReflectionIntensity;        // cb1[14].x 反射探针强度
    float  _ReflectionExposurePow;      // cb1[14].y 反射探针曝光指数
    float  _ReflectionExposureBias;     // cb1[14].w 反射探针曝光偏置
    float  _UsePrevPosUV2;              // cb1[32].x > 0 用 uv2 作为上一帧位置(positionCS2 输入选择)
CBUFFER_END

// ============================================================================
// 纹理(阴影贴图与 comparison 采样器由 Shadows.hlsl 声明,见其 t1/t2/s1/s2 注释;
// 反射探针用 URP 内置 unity_SpecCube0)
// ============================================================================
TEXTURE2D(_DiffuseTex);                 // t3 漫反射贴图
TEXTURE2D(_NormalTex);                  // t4 法线贴图
TEXTURE2D(_PBRParamTex);                // t5 参数贴图: r=roughness g=metallic b=occlusion a=贴花
TEXTURE2D(_RampMap);                    // t6 卡通渐变图

// ============================================================================
// 帧级全局(原 cb0 中无 URP 内置等价物的槽位,由 ShaolvRenderFeature 每帧设置)
// ============================================================================
CBUFFER_START(ShaolvPerFrame)
    float4x4 _EnvLightDirMatrix;        // cb0[1337..1339] 环境光方向旋转矩阵(卡通环境 ramp 用)
    float4   _EnvLightRefDir;           // cb0[1341] 环境光参考方向(翻转后使与主光夹角恒 > 90°)
    float4   _CascadeDepthBias;         // cb0[2721] 每级联沿主光方向偏移(icb 选择)
    float4   _CascadeNormalBias;        // cb0[2722] 每级联法线偏移(icb 选择,随 1-ndotl 缩放)
    float4   _ScreenSpaceDither;        // cb0[2782].xy 屏幕空间抖动偏移(o2.xy 加法项)
    float    _WindowMaskStrength;       // cb0[2757].x 窗户效果强度(o1.w = 0.5 - x*0.5)
CBUFFER_END

// ============================================================================
// 附加光数据(原 cb0[li+10]/[li+266]/[li+522]/[li+778],由 ShaolvRenderFeature 打包;
// 阴影矩阵/强度用 URP 内置 _AdditionalLightsWorldToShadow/_AdditionalShadowParams)
// ============================================================================
struct ShaolvAdditionalLightData
{
    float4 positionAndType;   // cb0[li+10]  xyz 光源位置; w = 0 方向光(lightDir = xyz)/ 1 位置光(lightDir = xyz - posWS)
    float4 color;             // cb0[li+266] 附加光颜色(含强度)
    float4 rangeSpot;         // cb0[li+522]  x = 1/range², z = 聚光衰减 scale, w = 聚光衰减 bias
    float4 spotDir;           // cb0[li+778]  xyz 聚光方向(世界)
};

StructuredBuffer<ShaolvAdditionalLightData> _ShaolvAdditionalLights;

#endif // SHAOLV_INPUT_INCLUDED
