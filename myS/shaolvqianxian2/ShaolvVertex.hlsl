// ShaolvQianxian2/ShaolvVertex.hlsl
// 顶点着色器,对应原始 asm VS 0-65 逐条移植。
// 变换(asm 0-7)用 URP 内置 TransformObjectToWorld/TransformWorldToHClip;法线/切线矩阵(asm 10-27,
// 原 cb1[4..6] 为物体矩阵旋转部分)用 TransformObjectToWorldNormal/Dir 后手动归一化(asm 10-16 的 dp3/rsq);
// 时间参数 cb0[1290].y 用 URP _Time.y;相机位置 cb0[1295] 用 _WorldSpaceCameraPos(GetWorldSpaceViewDir)。
#ifndef SHAOLV_VERTEX_INCLUDED
#define SHAOLV_VERTEX_INCLUDED

#include "ShaolvInput.hlsl"

struct ShaolvAttributes
{
    float4 positionOS    : POSITION;    // v0
    float3 normalOS      : NORMAL;      // v1
    float4 color         : COLOR;       // v2
    float2 uv            : TEXCOORD0;   // v3
    float2 uv1           : TEXCOORD1;   // v4
    float4 tangentOS     : TANGENT;     // v6
    float3 uv2           : TEXCOORD2;   // v7(原引擎存上一帧位置流)
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct ShaolvVaryings
{
    float4 uvAndUv1      : TEXCOORD0;   // o1  (uv, uv1)
    float4 worldNormal   : TEXCOORD1;   // o2  (xyz 归一化法线, w = positionWS.x)
    float4 worldTangent  : TEXCOORD2;   // o3  (xyz 归一化切线, w = positionWS.y)
    float4 worldBinormal : TEXCOORD3;   // o4  (xyz 副切线, w = positionWS.z)
    float4 color         : TEXCOORD4;   // o6  (顶点色, w = 0)
    float4 worldViewDir  : TEXCOORD5;   // o7  (xyz 未归一化视图方向, w = 时间变色噪声)
    float4 positionCS2   : TEXCOORD6;   // o11 (上一帧投影,PS 使用 xyw)
    float4 positionCS    : SV_Position; // o0/o10(冗余输出,URP 合并)
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

ShaolvVaryings ShaolvVert(ShaolvAttributes input)
{
    ShaolvVaryings output = (ShaolvVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    // asm 0-7: 对象->世界->裁剪
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float4 positionCS = TransformWorldToHClip(positionWS);

    // asm 8-9: uv / uv1 原样传递(uv 平铺偏移在 PS 内完成,对应 asm PS 1)
    output.uvAndUv1 = float4(input.uv, input.uv1);

    // asm 10-17: 法线变换 + 归一化(o2.w 存 positionWS.x)
    float3 normalWS = normalize(TransformObjectToWorldNormal(input.normalOS));
    output.worldNormal = float4(normalWS, positionWS.x);

    // asm 19-27: 切线变换 + 归一化(o3.w 存 positionWS.y)
    float3 tangentWS = normalize(TransformObjectToWorldDir(input.tangentOS.xyz));
    output.worldTangent = float4(tangentWS, positionWS.y);

    // asm 28-32: 副切线 = cross(法线, 切线) * (tangentOS.w * cb1[9].w)(已归一化向量的叉积无需再归一化)
    output.worldBinormal = float4(cross(normalWS, tangentWS) * (input.tangentOS.w * _TangentSign), positionWS.z);

    // asm 33-37: 世界坐标 / 顶点色(o5.w、o6.w 恒 0,PS 未使用)
    output.color = float4(input.color.rgb, 0.0);

    // asm 34: 视图方向(未归一化,PS 20-23 归一化;cb0[1295] = URP _WorldSpaceCameraPos)
    output.worldViewDir = float4(GetWorldSpaceViewDir(positionWS), 0.0);

    // asm 38-45: 时间变色噪声 v7.w
    //   r0.x = 1 - ((cos(cb0[1290].y * 5) + 1) * 0.35 + 0.2);cb0[1290].y = URP _Time.y
    //   r0.y = (1 - cb2[15].z) < 0.01 ? 1 : 0;asm 45 为 and 位运算(FXC select 优化产物),逐位还原
    float timeCos = cos(_Time.y * 5.0);
    float timeNoise = 1.0 - ((timeCos + 1.0) * 0.35 + 0.2);
    float timeFlag = (1.0 - _TimeTintEnabled) < 0.01 ? 1.0 : 0.0;
    output.worldViewDir.w = asfloat(asuint(timeNoise) & asuint(timeFlag));

    // asm 46-47: o8=(0,0,0,1) / o9=(0,0,0,0) 常量输出,PS 未使用,丢弃
    // asm 48-55: o10 与 o0 同公式(冗余投影),URP 合并为 SV_Position

    // asm 56-65: positionCS2 = 上一帧投影
    //   56-57: 输入位置选择 cb1[32].x > 0 用 v7(uv2 存上一帧位置),否则 positionOS
    //   58-61: 上一帧对象矩阵(cb1[24..27]) -> URP unity_MatrixPreviousM
    //   62-65: 上一帧视图投影(cb0[1352..1355]) -> URP _PrevViewProjMatrix
    float4 prevPositionOS = (_UsePrevPosUV2 > 0.0) ? float4(input.uv2, 1.0) : float4(input.positionOS.xyz, 1.0);
    float4 prevPositionWS = mul(unity_MatrixPreviousM, prevPositionOS);
    output.positionCS2 = mul(_PrevViewProjMatrix, prevPositionWS);

    output.positionCS = positionCS;
    return output;
}

#endif // SHAOLV_VERTEX_INCLUDED
