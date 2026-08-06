// NPRCharacter/NPRCharacterInput.hlsl
// 皮肤/脸部 URP 端口 —— 共享参数、全局常量与工具(自 ClothInput.hlsl 抽取改名,Cloth→Character)。
// 原始 skin.shader / face.shader 的 cb0/cb1/cb4/cb5 槽位一一对应,见各字段注释。
// 所有可调参数进入 UnityPerMaterial CBUFFER 以保证 SRP Batcher 兼容(材质属性在 SkinInput.hlsl / FaceInput.hlsl 声明);
// 帧级/体积 GI/雾参数为全局 CBUFFER(C# 每帧设置)。
#ifndef NPRCHARACTER_INPUT_INCLUDED
#define NPRCHARACTER_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"  // LerpWhiteTo(Shadows.hlsl:309 需要)
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

// ============================================================================
// 纹理(共享槽位;skin/face 槽位差异见注释,Unity 按名绑定。基础色/法线/雨/faceControl 在各自 Input 声明)
// 注:必须在本文件工具函数之前声明(HLSL 全局声明需先于使用)
// ============================================================================
TEXTURE2D(_RampTex);            // t6  漫反射 ramp
TEXTURE2D(_ColorGradeLUT);      // t7  颜色分级 LUT(skin/face 相同;cloth 的 t7 一图两用,此处只作 LUT)
TEXTURE2D(_MatCapTex);          // t10(skin)/ t14(face) MatCap
TEXTURE2D(_CharacterShadowTex); // t2  屏幕空间阴影 r=场景阴影 g=角色自阴影
TEXTURE3D(_VolumeIndex3D);      // t3  体积 GI 索引
TEXTURE3D(_VolumeLight3D);      // t4  体积 GI 光照
TEXTURE3D(_VolumeLightLowFreq3D);// t5  体积 GI 低频
TEXTURE3D(_FogLUT3D);           // t11(skin)/ t15(face) 雾 LUT

// ============================================================================
// 通用颜色工具(供所有模块使用)
// ============================================================================

// 亮度(asm 权重 0.2127/0.7152/0.0722,与 Unity Luminance 略有差异,以 asm 为准)
float CharacterLuminance(float3 c)
{
    return dot(c, float3(0.2127, 0.7152, 0.0722));
}

// AdjustSaturation(c, s) = lerp(Luminance(c), c, s)(skin asm 312-315 / face 366-369)
float3 AdjustCharacterSaturation(float3 c, float s)
{
    float lum = CharacterLuminance(c);
    return lerp(lum, c, s);
}

// 32×32 颜色分级 LUT(skin/face asm 2-18 逐条;URP 无等价 32 维 LUT 宏,照抄)
// 输入已为 sRGB;输出作为 gradBaseColor(shadowDiffuseColor 的基色)
float3 CharacterLinearToSRGB(float3 c)
{
    // asm 2-8:real LinearToSRGB(结果 movc_sat 逐分量 saturate)
    return saturate((c <= 0.0031) ? c * 12.92 : exp(log(abs(c)) * 0.4167) * 1.055 - 0.055);
}

float3 SampleCharacterColorGradeLUT(float3 c)
{
    // asm 9-12:uv0 = (round_ni(r*31)*0.0313 + g*0.0303 + 0.0005, b*0.9688 + 0.0156)
    float x = c.r * 31.0;
    float i = floor(x);                                  // round_ni = 向 -inf 取整
    float2 uv0 = float2(i * 0.0313 + c.g * 0.0303 + 0.0005, c.b * 0.9688 + 0.0156);
    // asm 13-15:双点采样,第二点 = uv0 + (0.0313, 0.0156 已在 uv0.y 内,asm 14 的 r2.w 无偏移)
    float3 t0 = SAMPLE_TEXTURE2D_LOD(_ColorGradeLUT, sampler_LinearClamp, uv0, 0.0).rgb;
    float3 t1 = SAMPLE_TEXTURE2D_LOD(_ColorGradeLUT, sampler_LinearClamp, float2(uv0.x + 0.0313, uv0.y), 0.0).rgb;
    // asm 16-18:frac 插值
    return lerp(t0, t1, x - i);
}

// HSV 饱和度/亮度修正(skin/face asm 155-196,chilliant RGBtoHCV;常数 0.35/0.7 照抄):
// 亮度越高饱和度越高,色相越接近红色饱和度越低;value = 2/(2-saturation)
float3 CharacterAdjustSHColor(float3 c)
{
    // RGBtoHCV begin (https://www.chilliant.com/rgb2hsv.html)
    float4 p = (c.g < c.b) ? float4(c.b, c.g, -1.0, 2.0 / 3.0) : float4(c.g, c.b, 0.0, -1.0 / 3.0);
    float4 q = (c.r < p.x) ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float chroma = q.x - min(q.w, q.y);
    float hue = abs((q.w - q.y) / (6.0 * chroma + 0.0001) + q.z);
    float saturation = chroma / (q.x + 0.0001);
    // RGBtoHCV end
    hue = frac(abs(hue));
    // 色相到终点距离 > 0.45 的边缘部分(越接近红色饱和度越低)
    float hueEdge = smoothstep(0.0, 1.0, saturate((abs(hue - 0.5) - 0.45) * -10.0));
    float satAdjusted = min(saturation, (0.7 - 0.35 * hueEdge) * saturate(q.x));
    float valAdjusted = 2.0 / (2.0 - satAdjusted);
    // HSVTORGB begin (https://github.com/przemyslawzaworski/Unity3D-CG-programming/blob/master/hsv.shader)
    float3 hsv = frac(hue + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0;
    float3 rgb = saturate(abs(hsv) - 1.0);
    rgb = lerp(float3(1, 1, 1), rgb, satAdjusted);
    // HSVTORGB end
    return rgb * valAdjusted;
}

// 内联 HSV 调整(skin asm 209-239 / face 192-222,MatCap 采样后使用)
float3 CharacterAdjustMatCapColor(float3 c)
{
    float4 p = (c.g < c.b) ? float4(c.b, c.g, -1.0, 2.0 / 3.0) : float4(c.g, c.b, 0.0, -1.0 / 3.0);
    float4 q = (c.r < p.x) ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float chroma = q.x - min(q.w, q.y);
    float hue = abs((q.w - q.y) / (6.0 * chroma + 0.0001) + q.z);
    float saturation = chroma / (q.x + 0.0001);
    float valAdjusted = 2.0 / (2.0 - saturation);
    float3 hsv = frac(abs(hue) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0;
    float3 rgb = saturate(abs(hsv) - 1.0);
    rgb = lerp(float3(1, 1, 1), rgb, saturation);
    return rgb * valAdjusted;
}

// ============================================================================
// 帧级全局(C# ClothFrameData 每帧设置,不属材质)
// _NonJitteredVP 对应原始 cb0[24..27];_PrevViewProjMatrix 直接使用 URP 已声明的全局
// (UnityInput.hlsl:274,非抖动运动矢量矩阵),不再重复声明。
// _FogEnabled 对应原始 cb0[171].w:雾整体开关(1=关,0=开)。原始 shader 中该槽位还参与
// 主光强度与 ambientIntensity 的 lerp(cb0[171].w → 1 时取 1),本实现按同名全局映射。
// ============================================================================
CBUFFER_START(CharacterPerFrame)
    float4x4 _NonJitteredVP;        // 原 cb0[24..27] 非抖动视图投影矩阵
    float  _FogEnabled;             // 原 cb0[171].w 雾开关(1=关;ClothFogVolume 挂载时置 0)
CBUFFER_END

// ============================================================================
// 体积 GI 全局(C# 侧体积 GI 组件填,本实现默认 URPProbe 模式不填)
// ============================================================================
CBUFFER_START(CharacterVolumeGI)
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
CBUFFER_START(CharacterFog)
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
// 附加光源风格化参数(由 StylizedLightRenderFeature 填充;布局与 ClothStylizedLightData 逐字段一致,
// C# 注入同一 StructuredBuffer。skin/face 原始 asm 的槽位偏移与 cloth 不同(idx*8+6..13),
// 语义位置相同,按语义映射;胶囊长度原在槽位 2.z,统一读 tangentAndCapsule.w 与 Cloth 端口一致)
// ============================================================================
struct CharacterStylizedLightData
{
    float4 colorAndType;         // rgb 颜色(含强度) w 类型(0点光 1聚光, >=2 跳过)
    float4 positionAndInvRadius; // xyz 位置 w 1/range
    float4 tangentAndCapsule;    // x,y 半八面体切线打包值 w 胶囊长度(0=非胶囊) z 预留(0)
    float4 modeParams0;          // xyz=(cosInner, cosOuter, 1/(cosInner-cosOuter)) w=renderMode(0-4)
    float4 modeParams1;          // 按模式复用(见 ApplySkinAdditionalLights / ApplyFaceAdditionalLights)
    float4 tangentWS;            // 全精度切线世界方向(f16 解包删除)
    float4 spotDirWS;            // xyz 聚光方向(全精度) w 非mode4衰减指数
    float4 specularParams;       // z=高光强度
};

StructuredBuffer<CharacterStylizedLightData> _StylizedLightParamsBuffer;

// ============================================================================
// 材质解码结果:与 skin/face asm PS 的寄存器一一对应
// ============================================================================
struct CharacterSurfaceData
{
    float3 baseColor;            // 基础色(rain 暗化后;face 含 faceControl 修正)
    float3 gradBaseColor;        // 颜色分级 LUT 结果(32×32 LUT)
    float  baseAlpha;            // 基础色 alpha(face 雨湿润后暗化;skin 未修正)
    float  metallic;             // _Metallic(0/1)
    float  specularStrength;     // f0 基(skin:雨区 lerp;face:faceControl.y 混合,湿润向 3 靠拢)
    float  roughness;            // skin:雨区标量修正;face:1-_Smoothness 或湿 0.3
    float  roughnessSqr;         // max(roughness^2, 0.0078)
    float3 diffuseColor;         // (0.96 - 0.96*metallic) * rimTintBaseColor
    float3 specularColor;        // lerp(specularStrength*0.04, rimTintBaseColor, metallic)
    float3 shadowDiffuseColor;   // (0.96 - 0.96*metallic) * gradBaseColor
    float3 normalTWS;            // 切线空间法线(背面翻转后;face 无 normalMap = 翻转几何法线)
    float3 normalWS;             // 几何法线(skin 翻转,face 不翻转 —— 以各自 asm 为准)
    float2 objectDir;            // normalize(positionWS.xz - 物体位置.xz)
    float2 NxzDir;               // skin: normalize(normalTWS.xz);face: normalize(lerp(objectDir, normalize(normalTWS.xz), faceControl.y))
    float  ndotv;                // 未钳制 dot(normalTWS, viewDirWS)
    float  ndotvTWS;             // saturate(ndotv)
    float3 viewDirWS;            // 归一化视线(表面指向相机)
    float  wetFactor;            // face 雨湿润因子(0=干);skin 恒 0
    float  wetRoughness;         // face 湿粗糙度(湿 0.3 / 干 1-_Smoothness);skin 恒 1-_Smoothness
    float3 wetNormal;            // face 湿润法线(干时 = normalTWS);skin 恒 normalTWS
    float4 faceControl;          // face 专用:_FaceControlTex 采样值(主光 SDF 混合/湿润控制用);skin 恒 0
    float  faceCamZ;             // face 专用:normalize(camVectorOS).z(asm 45;rim 修正与附加光 mode 3 用);skin 恒 0
};

// ============================================================================
// 主光阶段 → 附加光循环的共享状态(对应 asm 中跨段保留的寄存器)
// ============================================================================
struct CharacterLightingState
{
    float3 resultDiffuse;         // skin asm 372(r15.xzw)/ face 500(r14.xyz)
    float3 diffuseColor;          // s.diffuseColor
    float3 diffuseColorMinusHalf; // diffuseColor - 0.5(skin 543 / face 711)
    float3 gradBaseColor;         // 模式 1 阴影色基(skin 865 / face 1044,以 asm 为准:gradBaseColor 非 shadowDiffuseColor)
    float3 specularColor;         // s.specularColor
    float  roughnessSqr;          // s.roughnessSqr
    float  roughnessDelta;        // 0.01 - roughnessSqr(skin 545 / face 713,mode 2 用)
    float  ndotvTWS;              // 高光用 ndotv(skin: normalTWS 的 saturate;face: 湿润法线的 saturate)
    float  metallicFlag;          // (_Metallic >= 0.5) ? 1 : 0(skin 541 / face 699)
    float  mode0Scale;            // skin: 0.75-0.25*dominantOn;face: 0.75-0.25*curSceneShadow
    float  reverseNdotVx;         // 1 - |ndotv|(skin 425 / face 611)
    float3 camVector;             // UNITY_MATRIX_V._13_23_33(相机世界前向)
    float3 viewDirWS;             // s.viewDirWS
    // face 附加(face 的 asm 专有项)
    float  faceCamFactor;         // smoothstep(saturate(1.5-2*camZ))(face 448-451)
    float  faceCamZ;              // normalize(camVectorOS).z(face 45/620/1069)
    float  invWetControl;         // 1/(0.1+0.9*faceControl.y)(face 709-710)
    float  faceControlW;          // faceControl.w(face 631/1072)
    float  sdfAlpha;              // _FaceSDFTex.a(face 387/1038)
    float3 lightingNormal;        // SDF 扭曲法线(face 409/1027)
};

#endif // NPRCHARACTER_INPUT_INCLUDED
