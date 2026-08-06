// NPRCloth/ClothVertex.hlsl
// 顶点着色器,对应原始 asm VS 0-183 逐条移植。
// - 压缩法线/切线解码(asm 0-42):_CLOTH_PACKED_NORMALS 关键字控制(默认关,Unity 顶点流无 30bit uint 精度)
// - 蒙皮(asm 43-132):删除 —— Unity SkinnedMeshRenderer CPU 蒙皮已把 positionOS/normalOS/tangentOS 蒙皮后交 GPU
// - 变换(asm 133-183):URP 内置 TransformObjectToWorld / TransformWorldToHClip / GetWorldSpaceNormalizeViewDir
#ifndef NPRCLOTH_CLOTH_VERTEX_INCLUDED
#define NPRCLOTH_CLOTH_VERTEX_INCLUDED

#include "ClothInput.hlsl"

struct ClothAttributes
{
    float4 positionOS    : POSITION;
    float2 uv            : TEXCOORD0;
    float3 normalOS      : NORMAL;
    float4 tangentOS     : TANGENT;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct ClothVaryings
{
    float2 uv                : TEXCOORD0;
    float3 positionWS        : TEXCOORD1;
    float3 normalWS          : TEXCOORD2;    // 未翻转,PS 内翻转
    float4 tangentWS         : TEXCOORD3;    // xyz 切线, w = sign(tangentOS.w) * sign(_InstanceDirSign)
    float3 viewDirWS         : TEXCOORD4;
    float3 nonJitterScreenPos : TEXCOORD5;   // (非抖动CS.xy, 非抖动CS.w)
    float3 oldScreenPos      : TEXCOORD6;    // (旧CS.xy, 旧CS.w)
    float3 normalOS          : TEXCOORD7;
    float3 positionOS        : TEXCOORD8;
    float4 positionCS        : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// 压缩法线/切线解码(asm 0-42):3×10bit 位域 + 符号位,八面体解码 + 切线 2D 编码
float4 UnpackOctahedronNormalAndTangent(float packed)
{
    uint p = asuint(packed);
    uint3 bits = uint3(p & 0x3FFu, (p >> 10) & 0x3FFu, (p >> 20) & 0x3FFu);  // asm 2: ibfe 偏移 0/10/20
    uint signBit = p >> 31;                                                  // asm 3: 符号位

    float3 oct = float3(bits) * 0.002;   // asm 4-5: itof 后 *2/1023(≈0.002),映射到 [0, 2.046]
    // asm 6-16: 八面体解码
    //   r2 = (1-|y|, 1-|z|, 1-|y|); r3.z = 1-|y|-|z|; r2.x = (r3.z < 0)
    //   r0.yz = (1-|z|, 1-|y|)(X/Y 无符号恒 >= 0,符号位不参与法线);r3.xy = 折叠选择
    float3 n1 = float3(1.0 - abs(oct.y), 1.0 - abs(oct.z), 1.0 - abs(oct.y));
    float center = n1.x - abs(oct.z);
    float2 folded = (center < 0.0) ? float2(n1.y, n1.z) : oct.yz;
    float3 normal = normalize(float3(folded, center));   // asm 14-16

    // asm 17-27: perpendicular = normalize(normal.yzx - normal.zxy) 正交修正后, biPerp = normalize(cross(normal, perp))
    float3 perp = normalize(normal.yzx - normal.zxy);
    perp -= dot(perp, normal) * normal;
    perp = normalize(perp);
    float3 biPerp = normalize(cross(normal, perp));

    // asm 28-40: 切线 2D 编码解码
    //   signZ = (z < 0 ? -1 : 1)(无符号恒 1);factor = 2*z*signZ;r5 = (1-factor, signZ*(1-|1-factor|)) 归一化
    //   tangent = signZ*r5.x*perp + (1-|1-factor|)*biPerp;tangentSign = 2*signBit - 1
    float signZ = (oct.z < 0.0) ? -1.0 : 1.0;
    float factor = 2.0 * oct.z * signZ;
    float2 r5 = normalize(float2(1.0 - factor, signZ * (1.0 - abs(1.0 - factor))));
    float3 tangent = signZ * (r5.x * perp + r5.y * biPerp);
    float tangentSign = 2.0 * float(signBit) - 1.0;

    return float4(tangent, tangentSign);
}

ClothVaryings ClothVert(ClothAttributes input)
{
    ClothVaryings output = (ClothVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    float3 normalOS = input.normalOS;
    float4 tangentOS = input.tangentOS;
#if defined(_CLOTH_PACKED_NORMALS)
    // 顶点流带 30bit 打包数据时解码(asm 41-42 的选择分支)
    float4 unpacked = UnpackOctahedronNormalAndTangent(input.normalOS.x);
    normalOS = unpacked.xyz;
    tangentOS = unpacked;
#endif

    // 变换(asm 133-183)
    float3 positionOS = input.positionOS.xyz;
    float3 positionWS = TransformObjectToWorld(positionOS);
    float4 positionCS = TransformWorldToHClip(positionWS);

    // 归一化视图方向:URP 内置(内部已含正交相机分支,等价 asm 141-148 的 unity_OrthoParams.w lerp)
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);

    // 法线/切线(asm 150-163:dp3/max/rsq 归一化,与 URP Transform* 一致)
    float3 normalWS = TransformObjectToWorldNormal(normalOS);
    float3 tangentWS = TransformObjectToWorldDir(tangentOS.xyz);

    // 切线符号乘积(asm 178 + PS asm 33-37:sign(v3.w) * sign(cb1[inst+5].w))
    float tangentSign = sign(tangentOS.w) * sign(_InstanceDirSign);

    output.uv = TRANSFORM_TEX(input.uv, _BaseMap);          // asm 149: cb2[51]
    output.positionWS = positionWS;
    output.normalWS = normalWS;
    output.tangentWS = float4(tangentWS, tangentSign);
    output.viewDirWS = viewDirWS;
    output.positionCS = positionCS;
    output.normalOS = normalOS;
    output.positionOS = positionOS;

    // 非抖动屏幕坐标(asm 164-167:cb0[24..27] = _NonJitteredVP)
    output.nonJitterScreenPos = mul(_NonJitteredVP, float4(positionWS, 1.0)).xyw;

    // 上一帧屏幕坐标(asm 168-177):位置选择 cb1[inst+10].x < 1 ? positionOS : oldPositionOS。
    // Unity 顶点流无每顶点上一帧位置(蒙皮上一帧位置不提供,计划接受 ≈0 速度);
    // 非蒙皮物体用 unity_MatrixPreviousM(上一帧物体矩阵)计算旧位置。
    float4 oldPosCS = mul(_PrevViewProjMatrix, mul(unity_MatrixPreviousM, float4(positionOS, 1.0)));
    output.oldScreenPos = oldPosCS.xyw;

    return output;
}

#endif // NPRCLOTH_CLOTH_VERTEX_INCLUDED
