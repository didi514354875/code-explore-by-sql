#ifndef LIAN_CHARACTER_VERTEX_INCLUDED
#define LIAN_CHARACTER_VERTEX_INCLUDED

// LianCharacter VS(dump 线 2604-2683):positionWS、positionCS.z -= |w|×0.0064 深度偏移、
// uvs 打包(texcoord0/1)、normalWS.w=viewDir.x、tangentWS、binormalWS(含 tangentOS.w ×
// unity_WorldTransformParams.w)。

#include "LianCharacterInput.hlsl"

struct LianCharacterAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv0 : TEXCOORD0;
    float2 uv1 : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct LianCharacterVaryings
{
    float4 uv : TEXCOORD0;           // xy=uv0, zw=uv1
    float3 positionWS : TEXCOORD1;
    float4 normalWS : TEXCOORD2;     // xyz=normal, w=viewDir.x
    float4 tangentWS : TEXCOORD3;    // xyz=tangent, w=viewDir.y
    float4 binormalWS : TEXCOORD4;   // xyz=binormal, w=viewDir.z
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_OUTPUT_STEREO
};

LianCharacterVaryings LianCharacterVert(LianCharacterAttributes input)
{
    LianCharacterVaryings output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    // dump:positionCS.z -= abs(w) × 0.0064(深度偏移,防自遮挡)
    float4 positionCS = TransformWorldToHClip(positionWS);
    positionCS.z -= abs(positionCS.w) * 0.0063999998383224010467529296875;
    output.positionCS = positionCS;
    output.positionWS = positionWS;

    output.uv = float4(input.uv0, input.uv1);

    // viewDirWS(相机 → 表面),w 分量打包进 TBN 插值器(dump `_31.w/.w/.w`)
    float3 viewDirWS = _WorldSpaceCameraPos - positionWS;
    output.normalWS.w = viewDirWS.x;
    output.tangentWS.w = viewDirWS.y;
    output.binormalWS.w = viewDirWS.z;

    output.normalWS.xyz = TransformObjectToWorldNormal(input.normalOS);
    output.tangentWS.xyz = TransformObjectToWorldDir(input.tangentOS.xyz);
    output.binormalWS.xyz = cross(output.normalWS.xyz, output.tangentWS.xyz)
        * (input.tangentOS.w * unity_WorldTransformParams.w);
    return output;
}

#endif // LIAN_CHARACTER_VERTEX_INCLUDED
