// LianDepthLinear.shader — pass 8:1/2 分辨率线性深度 + 深度 buffer。
// dump `_31`(线 1442-1480):textureGather 相机深度 → 线性深度(color, R16G16F),
// gl_FragDepth = max(gather 四值)(深度, Depth24Stencil8)。
Shader "Hidden/LianYunShenKong/DepthLinear"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "DepthLinear"
            ZTest Always
            ZWrite On
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 4.5   // Gather 需要 SM5

            // Core.hlsl for XR dependencies
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"

            float4 _LianCameraDepthTexelSize;   // 由链内 pass 设置(1/宽, 1/高)

            struct FragmentOutput
            {
                float4 color : SV_Target0;
                float depth : SV_Depth;
            };

            FragmentOutput Frag(Varyings input)
            {
                // dump `_31`:gather 相机深度(2×2),线性深度用 gather 的 w 分量。
                // R32F 深度纹理不可线性过滤:用 Gather(返回原始四值,无过滤器)。
                float4 gathered = _CameraDepthTexture.Gather(sampler_PointClamp, input.texcoord);
                float linearDepth = rcp(_ZBufferParams.z * gathered.w + _ZBufferParams.w);

                float maxDepth = max(max(gathered.x, gathered.y), max(gathered.z, gathered.w));

                FragmentOutput output;
                output.color = float4(linearDepth, linearDepth, linearDepth, linearDepth);
                output.depth = maxDepth;
                return output;
            }
            ENDHLSL
        }
    }
}
