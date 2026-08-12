// LianShadowCaster.shader — pass 3/4:级联 + 特殊光 shadow map 投射(LightMode = LianShadowCaster)。
// VS 照 dump 线 633-669 / 769-806:normalWS→dot(_LightDirection)→(1-ndotl)×_ShadowBias.y 沿法线偏移,
// TransformWorldToHClip 后 positionCS.z += _ShadowBias.x(不用 URP ApplyShadowBias,差异见计划复用清单);
// PS 输出 positionCS.z/w(raw depth 0..1)到 _LianShadowAtlasTex(R32F 数组)。
// alpha 测试三变体(dump `_61`/`_62`/`_34`):_SCREEN_DOOR 屏幕门抖动 / _ALPHA_TEST alpha 截断。
Shader "Hidden/LianYunShenKong/ShadowCaster"
{
    Properties
    {
        _AlphaTex("Alpha Texture", 2D) = "white" {}
        _AlphaScale("Alpha Scale", Float) = 1.0
        _AlphaCutoff("Alpha Cutoff", Float) = 0.5
        _ScreenDoorBias("Screen Door Bias", Float) = 0.0
        _ShadowMipBias("Shadow Mip Bias", Float) = 0.0
        [Toggle(_SCREEN_DOOR)] _ScreenDoor("Screen Door", Float) = 0.0
        [Toggle(_ALPHA_TEST)] _AlphaTest("Alpha Test", Float) = 0.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "LianShadowCaster"
            Tags { "LightMode" = "LianShadowCaster" }

            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowCasterVertex
            #pragma fragment ShadowCasterFragment
            #pragma target 3.5

            // Material Keywords
            #pragma shader_feature_local _SCREEN_DOOR
            #pragma shader_feature_local _ALPHA_TEST

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // LerpWhiteTo(Shadows.hlsl:309 需要)
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"   // _ShadowBias

            // URP ShadowUtils.SetupShadowCasterConstantBuffer 设置的全局量(我们的 pass 主动绑定)
            float3 _LightDirection;

            TEXTURE2D(_AlphaTex);
            SAMPLER(sampler_AlphaTex);
            float _AlphaScale;
            float _AlphaCutoff;
            float _ScreenDoorBias;
            float _ShadowMipBias;

            // dump `_61`:DigitalRune 4×4 Screen-Door 抖动表(×1/17)
            static const float kScreenDoorPattern[16] = {
                1.0 / 17.0, 9.0 / 17.0, 3.0 / 17.0, 11.0 / 17.0,
                13.0 / 17.0, 5.0 / 17.0, 15.0 / 17.0, 7.0 / 17.0,
                4.0 / 17.0, 12.0 / 17.0, 2.0 / 17.0, 10.0 / 17.0,
                16.0 / 17.0, 8.0 / 17.0, 14.0 / 17.0, 6.0 / 17.0
            };

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings ShadowCasterVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                // dump:normalWS→(1 - clamp(dot(L, n))) × _ShadowBias.y 沿法线偏移
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float ndotl = saturate(dot(_LightDirection, normalWS));
                float scale = (1.0 - ndotl) * _ShadowBias.y;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                positionWS += normalWS * scale;

                // dump:投影后 positionCS.z += _ShadowBias.x(深度偏移;URP 的 ApplyShadowBias 数学不同,不复用)
                float4 positionCS = TransformWorldToHClip(positionWS);
                positionCS.z += _ShadowBias.x;

                // z 钳制照 URP ShadowCasterPass.hlsl 的 UNITY_REVERSED_Z 处理
                #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                output.positionCS = positionCS;
                output.uv = input.uv;
                return output;
            }

            // dump `_61`(屏幕门)/ `_62`(alpha 截断 + 屏幕门)/ `_34`(纯 alpha 截断)
            float4 ShadowCasterFragment(Varyings input) : SV_Target
            {
                #if defined(_SCREEN_DOOR) || defined(_ALPHA_TEST)
                float alpha = SAMPLE_TEXTURE2D_LOD(_AlphaTex, sampler_AlphaTex, input.uv, _ShadowMipBias).w;
                alpha = saturate(alpha * _AlphaScale);

                #if defined(_ALPHA_TEST)
                if (alpha - _AlphaCutoff < 0.0)
                    discard;
                #endif

                #if defined(_SCREEN_DOOR)
                {
                    float2 screenUV = input.positionCS.xy / input.positionCS.w * 0.5 + 0.5;
                    // dump:uv × 1024 → ×0.25 → fract → ×4 得 4×4 单元索引(uv∈[0,1] 时符号恒正)
                    float2 scaled = screenUV * 1024.0;
                    int2 cell = int2(fract(scaled * 0.25) * 4.0);
                    int ditherIndex = cell.y * 4 + cell.x;
                    if (alpha - kScreenDoorPattern[ditherIndex] - _ScreenDoorBias < 0.0)
                        discard;
                }
                #endif
                #endif

                // 缩放深度 0.5·z/w + 0.5(R32F 颜色目标;与采样 shadowDepth = 0.5·z+0.5 同约定,近→1 远→0)
                return float4(input.positionCS.z / input.positionCS.w * 0.5 + 0.5, 0.0, 0.0, 0.0);
            }
            ENDHLSL
        }
    }
}
