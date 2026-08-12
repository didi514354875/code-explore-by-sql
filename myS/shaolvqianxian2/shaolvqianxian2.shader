// ShaolvQianxian2/ShaolvQianxian2.shader
// 少女前线2 追放 角色 shader(原始 Assets/shaolvqianxian2/shaolvqianxian2.shader vs_4_0/ps_4_0 asm,
// hash ea8c3f8a / fce41795)的 URP 14.2.0-t1 复刻。
// 功能逻辑一对一按语义还原;与 URP 内置一致的函数/全局直接使用内置(变换、主光方向/颜色、
// 级联阴影矩阵/球/尺寸、SH 系数、反射探针、时间/相机/屏幕参数)。
// 原始 PS 输出 3 个渲染目标(o0 颜色 / o1 法线+遮罩 / o2 屏幕空间偏移),由 ShaolvRenderFeature
// (LightMode = ShaolvForward)绑定额外 RT 渲染;不挂 feature 时该 pass 不绘制。
// 模块:ShaolvInput.hlsl(参数) / ShaolvVertex.hlsl(VS) / ShaolvLighting.hlsl(PS)。
Shader "ShaolvQianxian2/Character"
{
    Properties
    {
        [MainTexture] _DiffuseTex("Diffuse Texture", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [Normal] _NormalTex("Normal Texture", 2D) = "bump" {}
        _PBRParamTex("PBR Param (R=Roughness G=Metallic B=Occlusion A=Decal)", 2D) = "white" {}
        _RampMap("Ramp Map", 2D) = "white" {}

        _TintColor("Tint Color", Color) = (1, 1, 1, 1)
        _DecalStrength("Decal Strength", Float) = 0.0
        _ShadowOffset("Shadow Offset", Float) = 0.05
        _TimeTintEnabled("Time Tint Enabled (>0.99)", Float) = 0.0
        _TimeTintColor("Time Tint Color (A=Intensity)", Color) = (1, 1, 1, 0)
        _CascadeShadowOn("Cascade Shadow On (>0)", Float) = 1.0
        _ToonOn("Toon On (>0)", Float) = 0.0
        _SHDetailRemoval("SH Detail Removal (>0)", Float) = 0.0
        _TangentSign("Tangent Sign", Float) = 1.0
        _MaxAdditionalLights("Max Additional Lights", Float) = 4.0
        _ReflectionIntensity("Reflection Intensity", Float) = 1.0
        _ReflectionExposurePow("Reflection Exposure Pow", Float) = 1.0
        _ReflectionExposureBias("Reflection Exposure Bias", Float) = 0.0
        _UsePrevPosUV2("Use Prev Position UV2 (>0)", Float) = 0.0
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
        // 主 pass:由 ShaolvRenderFeature 注入渲染(绑定颜色 + 法线遮罩 + 屏幕偏移 3 个 RT)
        // ==================================================================
        Pass
        {
            Name "ShaolvForward"
            Tags { "LightMode" = "ShaolvForward" }

            ZWrite On
            Cull Back
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShaolvVert
            #pragma fragment ShaolvFrag

            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

            // Unity defined keywords
            #pragma multi_compile_instancing

            #include "ShaolvLighting.hlsl"
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
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // ShadowCaster:照抄 Lit.shader,URP Shadows.hlsl ApplyShadowBias
        // ==================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"  // LerpWhiteTo
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // ==================================================================
        // Meta:照抄 Lit.shader 结构,输出 _DiffuseTex * _BaseColor
        // ==================================================================
        Pass
        {
            Name "Meta"
            Tags { "LightMode" = "Meta" }

            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex UniversalVertexMeta
            #pragma fragment ShaolvMetaFrag

            #include "ShaolvInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UniversalMetaPass.hlsl"

            half4 ShaolvMetaFrag(Varyings input) : SV_Target
            {
                MetaInput metaInput;
                metaInput.Albedo = SAMPLE_TEXTURE2D(_DiffuseTex, sampler_LinearRepeat, input.uv).rgb * _BaseColor.rgb;
                metaInput.Emission = 0;
                return UniversalFragmentMeta(input, metaInput);
            }
            ENDHLSL
        }
    }
    // Fallback 空:无降级材质
}
