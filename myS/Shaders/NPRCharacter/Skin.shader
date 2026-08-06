// NPRCharacter/Skin.shader
// 明日方舟终末地风格卡通皮肤 —— 原始 Assets/Resources/Shaders/skin.shader (vs_5_0/ps_5_0 asm,1422 行) 的 URP 14.2.0-t1 复刻。
// 变量名按 asm 注释语义命名、按数据流模块化;URP 有等价物的(变换/主光/附加光衰减与阴影/SH/反射探针)直接使用 URP 内置函数。
// 模块:SkinInput.hlsl(材质参数) / NPRCharacterInput.hlsl(共享参数与工具) / NPRCharacterVertex.hlsl(VS) /
//       NPRCharacterGI.hlsl(环境光) / NPRCharacterLighting.hlsl(共享光照工具) /
//       NPRCharacterFog.hlsl(雾与运动矢量) / SkinLighting.hlsl(材质解码+主光+附加光+输出)。
Shader "NPRCharacter/Skin"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalScale("Normal Scale", Float) = 1.0

        _ColorGradeLUT("Color Grade LUT", 2D) = "white" {}
        _RampTex("Diffuse Ramp", 2D) = "white" {}

        _Smoothness("Smoothness", Float) = 0.5
        _SpecularStrength("Specular Strength", Float) = 0.5
        _Metallic("Metallic", Float) = 0.0

        _RimTintStrength("Rim Tint Strength", Float) = 0.0
        _RimTintColor("Rim Tint Color", Color) = (1, 1, 1, 1)

        [Toggle(_DOUBLE_SIDED)] _DoubleSided("Double Sided", Float) = 0.0
        _DoubleSidedFlip("Double Sided Flip", Float) = 1.0
        [HideInInspector] _Cull("__cull", Float) = 2.0

        _MatCapTex("MatCap", 2D) = "white" {}
        _CharacterShadowTex("Character Shadow (R=Scene G=Self)", 2D) = "white" {}

        _VolumeIndex3D("Volume GI Index", 3D) = "white" {}
        _VolumeLight3D("Volume GI Light", 3D) = "white" {}
        _VolumeLightLowFreq3D("Volume GI Light LowFreq", 3D) = "white" {}
        _FogLUT3D("Fog LUT", 3D) = "white" {}

        _MainLightDirOverride("Main Light Dir Override", Vector) = (0, 0, 0, 0)
        _CharacterLightBlend("Character Light Blend", Float) = 0.0
        _MainLightColorOverride("Main Light Color Override", Color) = (1, 1, 1, 1)
        _LightColorOverrideBlend("Light Color Override Blend", Float) = 0.0

        _BackLightControl("Back Light Control", Float) = 1.0
        _BackLightBias("Back Light Bias", Float) = 0.0

        _ShadowStrength("Shadow Strength", Float) = 1.0
        _LightRadianceScale("Light Radiance Scale", Float) = 1.0
        _EnvIntensity("Env Intensity", Float) = 1.0
        _SceneShadowMix("Scene Shadow Mix", Float) = 0.0

        [KeywordEnum(Volume, Const, MatCap, URPProbe)] _GI_MODE("GI Mode", Float) = 3.0
        _BakedGIStrength("Baked GI Strength", Float) = 1.0
        _SHColorConst("SH Color Const", Color) = (0.5, 0.5, 0.5, 1)
        _MatCapMix("MatCap Mix", Float) = 1.0
        _AmbientIntensityMix("Ambient Intensity Mix", Float) = 1.0
        _AmbientBase("Ambient Base", Float) = 1.0

        _SkyDir("Sky Dir", Vector) = (0, 1, 0, 0)
        _SkyOffset("Sky Offset", Float) = 0.0
        _SkyScale("Sky Scale", Float) = 1.0
        _SkyBias("Sky Bias", Float) = 0.0

        _RimColor("Rim Color", Color) = (0, 0, 0, 0)
        _RimDir("Rim Dir", Vector) = (0, 1, 0, 0)
        _RimRange("Rim Range", Float) = 0.0
        _RimFresnelMix("Rim Fresnel Mix", Float) = 0.0

        _RainAreaCenter("Rain Area Center", Vector) = (0, 0, 0, 0)
        _RainAreaControl("Rain Area Control (X=Blend Y=CenterX Z=Tiling W=CenterY)", Vector) = (0, 0, 1, 0)
        _InstanceDirSign("Instance Dir Sign", Float) = 1.0

        _ShadowTexIntensity("Shadow Tex Intensity", Float) = 1.0
        _SceneShadowFallback("Scene Shadow Fallback", Float) = 1.0
        _Exposure("Exposure", Float) = 1.0
        _MipBias("Mip Bias", Float) = 0.0
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
        // 主 pass:UniversalForward
        // ==================================================================
        Pass
        {
            Name "SkinForward"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            Cull [_Cull]
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0          // 10 个插值器(TEXCOORD0-9)需要 SM3.0+
            #pragma vertex CharacterVert
            #pragma fragment SkinFrag

            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            // 注:URP 14 附加光阴影关键字为单数 _ADDITIONAL_LIGHT_SHADOWS(Shadows.hlsl:21)
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_ON

            // Unity defined keywords
            #pragma multi_compile_instancing

            // Material Keywords
            #pragma shader_feature_local _CHARACTER_PACKED_NORMALS
            #pragma shader_feature_local _SCENE_SHADOW_TEX
            #pragma shader_feature_local _DOUBLE_SIDED
            #pragma shader_feature_local_fragment _GI_MODE_VOLUME _GI_MODE_CONST _GI_MODE_MATCAP _GI_MODE_URPPROBE
            #pragma shader_feature_local_fragment _FOG_LUT_3D

            // 自定义雾,不声明 multi_compile_fog
            #include "SkinInput.hlsl"
            #include "NPRCharacterInput.hlsl"
            #include "NPRCharacterVertex.hlsl"
            #include "NPRCharacterGI.hlsl"
            #include "NPRCharacterLighting.hlsl"
            #include "NPRCharacterFog.hlsl"
            #include "SkinLighting.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // DepthOnly:照抄包内 Lit.shader 同结构,顶点只算 positionCS
        // ==================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // Material Keywords
            #pragma shader_feature_local _DOUBLE_SIDED

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // ShadowCaster:照抄 Lit.shader,URP Shadows.hlsl ApplyShadowBias(:482)
        // ==================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"  // LerpWhiteTo(Shadows.hlsl:309 需要,该 pass 不包含 SkinInput)
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // Meta:照抄 Lit.shader 结构,输出 _BaseMap * _BaseColor
        // ==================================================================
        Pass
        {
            Name "Meta"
            Tags { "LightMode" = "Meta" }

            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex UniversalVertexMeta
            #pragma fragment SkinMetaFrag

            #include "SkinInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UniversalMetaPass.hlsl"

            half4 SkinMetaFrag(Varyings input) : SV_Target
            {
                MetaInput metaInput;
                metaInput.Albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_LinearRepeat, input.uv).rgb * _BaseColor.rgb;
                metaInput.Emission = 0;
                return UniversalFragmentMeta(input, metaInput);
            }
            ENDHLSL
        }

        // ==================================================================
        // 运动矢量 pass:由 ClothMotionVectorRenderFeature(默认禁用)二次渲染输出
        // _MOTION_VECTOR_PASS 关键字打开时输出 EncodeCharacterMotionVector 结果
        // ==================================================================
        Pass
        {
            Name "ClothMotionVectors"
            Tags { "LightMode" = "ClothMotionVectors" }

            ZWrite On
            Cull [_Cull]
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CharacterVert
            #pragma fragment SkinFragMotionVector

            // Material Keywords
            #pragma shader_feature_local _DOUBLE_SIDED
            #pragma shader_feature_local_fragment _MOTION_VECTOR_PASS

            #pragma multi_compile_instancing

            #include "SkinInput.hlsl"
            #include "NPRCharacterInput.hlsl"
            #include "NPRCharacterVertex.hlsl"
            #include "NPRCharacterGI.hlsl"
            #include "NPRCharacterLighting.hlsl"
            #include "NPRCharacterFog.hlsl"
            #include "SkinLighting.hlsl"
            ENDHLSL
        }
    }
    // Fallback 空:无降级材质
}
