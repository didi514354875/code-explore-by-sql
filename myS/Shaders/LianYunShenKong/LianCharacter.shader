// LianYunShenKong/LianCharacter.shader
// 恋与深空风格角色材质 — 对应 dump lianyushengkong.shader 的角色相关 pass。
// LightMode 契约:LianPrePass(pass 5)/ LianSkin(pass 16)/ LianCharacter(pass 20)/ LianShadowCaster(pass 3/4)。

Shader "LianYunShenKong/LianCharacter"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map (RGB albedo, A alpha)", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _ParamMap("Param Map (R=metallic, G=profile, B=roughness)", 2D) = "white" {}
        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        _DetailNormalMap("Detail Normal Map", 2D) = "bump" {}
        _DetailTex("Detail Tex (RGB, A=blend)", 2D) = "white" {}
        _TintMask("Tint Mask", 2D) = "white" {}
        _DecalTex("Decal Tex", 2D) = "white" {}

        _ColorTint("Color Tint", Color) = (1, 1, 1, 1)
        _AlbedoMColor("AlbedoM Color", Color) = (1, 1, 1, 1)
        _AlbedoMMix("AlbedoM Mix", Float) = 0.0
        _DecalColor("Decal Color", Color) = (1, 1, 1, 1)
        _TintControlBase("Tint Control Base", Color) = (1, 1, 1, 1)
        _TintMaskWeights("Tint Mask Weights", Vector) = (1, 0, 0, 0)
        _BrightM("BrightM", Float) = 1.0
        _Specular("Specular", Float) = 0.5
        _OutputAlpha("Output Alpha", Float) = 1.0

        _EnvCube("Env Cube", Cube) = "white" {}
        _EnvIntensity("Env Intensity", Float) = 1.0
        _EnvPower("Env Power", Float) = 1.0
        _EnvAlphaLerp("Env Alpha Lerp", Float) = 0.0

        _SkyLightDir("Sky Light Dir", Vector) = (0, 1, 0, 0)
        _SkyLightColor("Sky Light Color", Color) = (0.5, 0.5, 0.6, 1)
        _MainLightColor("Main Light Color", Color) = (1, 1, 1, 1)
        _ShadowStrength("Shadow Strength", Float) = 1.0
        _BakedGIBlend("Baked GI Blend", Float) = 1.0
        _BakedGIOffset("Baked GI Offset", Vector) = (0, 0, 0, 0)
        _GILerp("GI Lerp", Float) = 0.0
        _BakedGIStrength("Baked GI Strength", Float) = 1.0
        _HeightOffset("Height Offset", Float) = 0.0
        _HeightFactor("Height Factor", Float) = 0.0
        _NormalSelectRight("Normal Select Right", Float) = 0.5
        _NormalSelectLeft("Normal Select Left", Float) = 0.5
        _AlphaScale("Alpha Scale", Float) = 1.0
        _AlphaCutoff("Alpha Cutoff", Float) = 0.5
        _ScreenDoorBias("Screen Door Bias", Float) = 0.0
        _ShadowMipBias("Shadow Mip Bias", Float) = 0.0

        // 雾(dump `_37`)
        _FogWindDirA("Fog Wind Dir A", Vector) = (1, 0, 0, 1)
        _FogLUTDepthScale("Fog LUT Depth Scale", Float) = 1.0
        _FogDirInscatColor("Fog Dir Inscat Color", Color) = (1, 1, 1, 1)
        _FogDirStartDist("Fog Dir Start Dist", Float) = 0.0
        _FogStartDist("Fog Start Dist", Float) = 0.0
        _FogDensity("Fog Density", Vector) = (1, 1, 0, 0)
        _FogVolumetricAlbedo("Fog Volumetric Albedo", Color) = (1, 1, 1, 1)
        _FogBlendOffset("Fog Blend Offset", Float) = 0.0
        _FogBlendScale("Fog Blend Scale", Float) = 1.0
        _FogVolumeOrigin("Fog Volume Origin", Vector) = (0, 0, 0, 0)
        _FogLUT3D("Fog LUT 3D", 3D) = "white" {}

        [Toggle(_MV_QUANTIZE)] _MV_QUANTIZE("运动矢量抖动量化", Float) = 0.0
        [IntRange] _MV_QUANTIZE_BITS("量化位数(bit0-1=MotionVector, bit2-3=Normal; 1=4bit, 2=5bit, 3=5/6/5bit)", Int) = 0
        [Toggle(_SCREEN_DOOR)] _ScreenDoor("Screen Door", Float) = 0.0
        [Toggle(_ALPHA_TEST)] _AlphaTest("Alpha Test", Float) = 0.0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        // ==================================================================
        // pass 5 预处理 MRT:输出 _LianMotionVectorTex(SV_Target0) +
        // _LianNormalTex(SV_Target1),深度写入相机深度(dump `_43`,线 435-534)
        // ==================================================================
        Pass
        {
            Name "LianPrePass"
            Tags { "LightMode" = "LianPrePass" }

            ZWrite On
            ZTest LEqual
            Cull Back
            Blend Off

            HLSLPROGRAM
            #pragma vertex LianPrePassVertex
            #pragma fragment LianPrePassFragment
            #pragma target 3.5

            // Material Keywords
            #pragma shader_feature_local _MV_QUANTIZE

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "LianShared.hlsl"

            int _MV_QUANTIZE_BITS;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 nonJitterPositionCS : TEXCOORD0;   // dump `_25`
                float4 previousPositionCS : TEXCOORD1;    // dump `_26`
                float3 normalWS : TEXCOORD2;              // dump `_28`
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings LianPrePassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                // dump 原引擎为相机相对渲染(unity_MatrixVP 无平移);Unity 的 unity_MatrixVP
                // 含相机平移,直接套用"减 cameraPos 再投影"会产生双重平移,故用标准投影,画面一致。
                output.positionCS = TransformWorldToHClip(positionWS);
                output.nonJitterPositionCS = mul(_NonJitteredViewProjMatrix, float4(positionWS, 1.0));
                // 旧位置:Unity 无 oldPositionOS 顶点属性,静态网格上一帧 OS 位置 = 当前 positionOS;
                // 相机运动产生的运动矢量由 _PrevViewProjMatrix 体现(dump `_12._m14.x` 分支保留于参数层)。
                float3 oldPositionWS = mul(GetPrevObjectToWorldMatrix(), float4(input.positionOS.x, input.positionOS.y, input.positionOS.z, 1.0)).xyz;
                output.previousPositionCS = mul(_PrevViewProjMatrix, float4(oldPositionWS, 1.0));
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            struct FragmentOutput
            {
                half4 motion : SV_Target0;   // _LianMotionVectorTex
                half4 normal : SV_Target1;   // _LianNormalTex
            };

            FragmentOutput LianPrePassFragment(Varyings input)
            {
                FragmentOutput output;

                // dump `_43`:NDC 空间运动差值 [-2,2] → 8bit 高低字节打包
                float2 motion = input.nonJitterPositionCS.xy / input.nonJitterPositionCS.w
                              - input.previousPositionCS.xy / input.previousPositionCS.w;
                float4 encodedMV = LianEncodeMotionVector(motion);

                // dump `_43`:法线球面映射编码(z 通道 0.495/0.505 正反标记)
                float3 n = normalize(input.normalWS);
                float3 encodedNormal = LianEncodeNormalSpheremap(n);

                // dump `_2` constant_id 抖动量化(默认关)
                #ifdef _MV_QUANTIZE
                {
                    float dither = LianBayer2x2Value(input.positionCS.xy);

                    uint mvBits = uint(_MV_QUANTIZE_BITS) & 3u;
                    if (mvBits == 1u) { encodedMV.xyz = round((encodedMV.xyz + dither * 2.0) * 15.0) / 15.0; }
                    else if (mvBits == 2u) { encodedMV.xyz = round((encodedMV.xyz + dither) * 31.0) / 31.0; }
                    else if (mvBits == 3u)
                    {
                        float3 d = float3(dither, dither * 0.5, dither);
                        float3 lv = float3(31.0, 63.0, 31.0);
                        encodedMV.xyz = round((encodedMV.xyz + d) * lv) / lv;
                    }

                    uint nBits = (uint(_MV_QUANTIZE_BITS) >> 2u) & 3u;
                    if (nBits == 1u) { encodedNormal.xyz = round((encodedNormal.xyz + dither * 2.0) * 15.0) / 15.0; }
                    else if (nBits == 2u) { encodedNormal.xyz = round((encodedNormal.xyz + dither) * 31.0) / 31.0; }
                    else if (nBits == 3u)
                    {
                        float3 d = float3(dither, dither * 0.5, dither);
                        float3 lv = float3(31.0, 63.0, 31.0);
                        encodedNormal.xyz = round((encodedNormal.xyz + d) * lv) / lv;
                    }
                }
                #endif

                output.motion = half4(encodedMV);
                output.normal = half4(encodedNormal.x, encodedNormal.y, encodedNormal.z, 0.0);
                return output;
            }
            ENDHLSL
        }

        // ==================================================================
        // pass 16 皮肤 diffuse + profile MRT(dump `_85`)
        // ==================================================================
        Pass
        {
            Name "LianSkin"
            Tags { "LightMode" = "LianSkin" }

            ZWrite On
            ZTest LEqual
            Cull Back
            Blend Off

            HLSLPROGRAM
            #pragma vertex LianCharacterVert
            #pragma fragment LianSkinFrag
            #pragma target 3.5

            #pragma multi_compile_instancing

            #include "LianCharacterSkin.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // pass 20 角色最终着色 → _CameraColorTexture(dump `_134`)
        // ==================================================================
        Pass
        {
            Name "LianCharacter"
            Tags { "LightMode" = "LianCharacter" }

            ZWrite On
            ZTest LEqual
            Cull Back
            Blend Off

            HLSLPROGRAM
            #pragma vertex LianCharacterVert
            #pragma fragment LianCharacterFrag
            #pragma target 3.5

            #pragma multi_compile_instancing

            #include "LianCharacterRender.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // pass 3/4 阴影投射(角色材质补该 LightMode;实际阴影渲染用 feature 的
        // override 材质 Hidden/LianYunShenKong/ShadowCaster)
        // ==================================================================
        Pass
        {
            Name "LianShadowCaster"
            Tags { "LightMode" = "LianShadowCaster" }

            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma vertex LianShadowCasterVertex
            #pragma fragment LianShadowCasterFragment
            #pragma target 3.5

            #pragma shader_feature_local _SCREEN_DOOR
            #pragma shader_feature_local _ALPHA_TEST

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // LerpWhiteTo(Shadows.hlsl:309 需要)
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "LianCharacterInput.hlsl"

            float3 _LightDirection;

            static const float kScreenDoorPattern[16] = {
                1.0 / 17.0, 9.0 / 17.0, 3.0 / 17.0, 11.0 / 17.0,
                13.0 / 17.0, 5.0 / 17.0, 15.0 / 17.0, 7.0 / 17.0,
                4.0 / 17.0, 12.0 / 17.0, 2.0 / 17.0, 10.0 / 17.0,
                16.0 / 17.0, 8.0 / 17.0, 14.0 / 17.0, 6.0 / 17.0
            };

            struct LianShadowCasterAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct LianShadowCasterVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            LianShadowCasterVaryings LianShadowCasterVertex(LianShadowCasterAttributes input)
            {
                LianShadowCasterVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float ndotl = saturate(dot(_LightDirection, normalWS));
                float scale = (1.0 - ndotl) * _ShadowBias.y;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                positionWS += normalWS * scale;
                float4 positionCS = TransformWorldToHClip(positionWS);
                positionCS.z += _ShadowBias.x;
                #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                output.positionCS = positionCS;
                output.uv = input.uv;
                return output;
            }

            float4 LianShadowCasterFragment(LianShadowCasterVaryings input) : SV_Target
            {
                #if defined(_SCREEN_DOOR) || defined(_ALPHA_TEST)
                float alpha = saturate(SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, input.uv, _ShadowMipBias).w * _AlphaScale);
                #if defined(_ALPHA_TEST)
                if (alpha - _AlphaCutoff < 0.0)
                    discard;
                #endif
                #if defined(_SCREEN_DOOR)
                {
                    float2 screenUV = input.positionCS.xy / input.positionCS.w * 0.5 + 0.5;
                    float2 scaled = screenUV * 1024.0;
                    int2 cell = int2(fract(scaled * 0.25) * 4.0);
                    int ditherIndex = cell.y * 4 + cell.x;
                    if (alpha - kScreenDoorPattern[ditherIndex] - _ScreenDoorBias < 0.0)
                        discard;
                }
                #endif
                #endif
                return float4(input.positionCS.z / input.positionCS.w * 0.5 + 0.5, 0.0, 0.0, 0.0);
            }
            ENDHLSL
        }
    }
    // Fallback 空:无降级材质
}
