// LianFogNoise.shader — pass 1:程序化雾 noise,输出 _LianFogNoiseTex(R8G8B8A8)。
// dump `_53`(线 231-322):uv 缩放偏移 → 4 次 textureLod × 0.01 累加 →
// _RippleEnabled > 0.5 时叠加 4 层波纹 → 输出 xzy 交换。
// 材质由 feature 的 _fogNoiseMaterial 提供;_NoiseTex 为该材质的噪声贴图。
Shader "Hidden/LianYunShenKong/FogNoise"
{
    Properties
    {
        _NoiseTex("Noise Texture", 2D) = "white" {}
        _NoiseRange("Noise Range (xy=min, zw=max)", Vector) = (0, 0, 1, 1)
        _NoiseScale("Noise Scale (xy)", Vector) = (1, 1, 0, 0)
        _NoiseUvScale("Noise UV Scale (x,y=sample1, z,w=sample2)", Vector) = (1, 1, 1, 1)
        _NoiseUvOffsetA("Noise UV Offset A (samples 1,2)", Vector) = (0, 0, 0, 0)
        _NoiseUvOffsetB("Noise UV Offset B (samples 3,4)", Vector) = (0, 0, 0, 0)
        _NoiseSampleScale("Noise Sample Scale (xy per sample)", Vector) = (1, 1, 1, 1)
        _NoiseSampleZScale("Noise Sample Z Scale", Vector) = (1, 1, 1, 1)
        _RippleEnabled("Ripple Enabled", Float) = 0.0
        _RippleDir12("Ripple Dir 1,2", Vector) = (1, 0, 0, 1)
        _RippleDir34("Ripple Dir 3,4", Vector) = (1, 0, 0, 1)
        _RippleStrength("Ripple Strength (x=base, y=delta)", Vector) = (0, 0, 0, 0)
        _RippleAmplitude("Ripple Amplitude (x,y,z,w)", Vector) = (0.1, 0.1, 0.1, 0.1)
        _RippleDistRange("Ripple Dist Range (x=start, y=end)", Vector) = (0, 10, 0, 0)
        _RipplePhase("Ripple Phase (x,y)", Vector) = (0, 0, 0, 0)
        _RippleCenter("Ripple Center (xy)", Vector) = (0.5, 0.5, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "FogNoise"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            // Core.hlsl for XR dependencies
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            float4 _NoiseRange;
            float4 _NoiseScale;
            float4 _NoiseUvScale;
            float4 _NoiseUvOffsetA;
            float4 _NoiseUvOffsetB;
            float4 _NoiseSampleScale;
            float4 _NoiseSampleZScale;
            float _RippleEnabled;
            float4 _RippleDir12;
            float4 _RippleDir34;
            float4 _RippleStrength;
            float4 _RippleAmplitude;
            float4 _RippleDistRange;
            float4 _RipplePhase;
            float4 _RippleCenter;

            half4 Frag(Varyings input) : SV_Target
            {
                // dump `_53`:range = lerp(_m17.xy, _m17.zw, uv); scaled = range * _m55.xy
                float2 range = lerp(_NoiseRange.xy, _NoiseRange.zw, input.texcoord);
                float2 scaled = range * _NoiseScale.xy;

                // 4 个采样 UV:scaled.xyxy * _m4.xxyy + _m6 / scaled.xyxy * _m4.zzww + _m7
                float2 uvA = scaled.xyxy * _NoiseUvScale.xxyy + _NoiseUvOffsetA.xy;
                float2 uvB = scaled.xyxy * _NoiseUvScale.zzww + _NoiseUvOffsetA.zw;
                float2 uvC = scaled.xyxy * _NoiseUvScale.xxyy + _NoiseUvOffsetB.xy;
                float2 uvD = scaled.xyxy * _NoiseUvScale.zzww + _NoiseUvOffsetB.zw;

                float3 s1 = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, uvA, 0.0).xyz;
                float3 s2 = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, uvB, 0.0).xyz;
                float3 s3 = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, uvC, 0.0).xyz;
                float3 s4 = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, uvD, 0.0).xyz;

                // xy 与 z 分别缩放,累加 × 0.01(dump 细节强度)
                float3 result = 0.0;
                result += s1 * float3(_NoiseSampleScale.x, _NoiseSampleScale.x, _NoiseSampleZScale.x);
                result += s2 * float3(_NoiseSampleScale.y, _NoiseSampleScale.y, _NoiseSampleZScale.y);
                result += s3 * float3(_NoiseSampleScale.z, _NoiseSampleScale.z, _NoiseSampleZScale.z);
                result += s4 * float3(_NoiseSampleScale.w, _NoiseSampleScale.w, _NoiseSampleZScale.w);
                result *= 0.00999999977648258209228515625;

                // 4 层波纹(dump `_14._m60 > 0.5`)
                if (_RippleEnabled > 0.5)
                {
                    float v1 = dot(_RippleDir12.xy, scaled);
                    float v2 = dot(_RippleDir12.zw, scaled);
                    float v3 = dot(_RippleDir34.xy, scaled);
                    float v4 = dot(_RippleDir34.zw, scaled);

                    float2 distVec = -range * _NoiseScale.xy + _RippleCenter.xy;
                    float len = length(distVec);
                    float distF = saturate((len - _RippleDistRange.x) / (_RippleDistRange.y - _RippleDistRange.x + 0.00999999977648258209228515625));
                    distF = 1.0 - distF;
                    // lerp(_RippleStrength.x + _RippleStrength.y, _RippleStrength.x, distF) 展开
                    float falloff = _RippleStrength.x + _RippleStrength.y * (1.0 - distF);

                    // 角速度 0.4 / 0.2 / 0.2 / 0.6(dump 常量)
                    float angle1 = v1 * 0.4000000059604644775390625 - _RipplePhase.x;
                    float angle2 = v2 * 0.20000000298023223876953125 - _RipplePhase.y;
                    float angle3 = v3 * 0.20000000298023223876953125 - _RipplePhase.y;
                    float angle4 = v4 * 0.60000002384185791015625 - _RipplePhase.x;

                    result += float3(sin(angle1) * _RippleAmplitude.x * _RippleDir12.xy, cos(angle1) * falloff);
                    result += float3(sin(angle2) * _RippleAmplitude.y * _RippleDir12.zw, cos(angle2) * falloff);
                    result += float3(sin(angle3) * _RippleAmplitude.z * _RippleDir34.xy, cos(angle3) * falloff);
                    result += float3(sin(angle4) * _RippleAmplitude.w * _RippleDir34.zw, cos(angle4) * falloff);
                }

                // dump:输出 xzy 交换,w = 0
                return half4(result.x, result.z, result.y, 0.0);
            }
            ENDHLSL
        }
    }
}
