// LianDoFCoC.shader — pass 21:计算 CoC radius 存入 alpha(dump `_53`,线 3745-3789)。
// 世界重建 → viewLen → 对焦曲线(farNearFocus)→ cocFactor(远正近负)→
// cocRadius = cocFactor·强度·screenWidth·0.5;sceneColor.a < 0.001 置 0;rgb 调暗。
Shader "Hidden/LianYunShenKong/DoFCoC"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "DoFCoC"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            SAMPLER(sampler_BlitTexture);


            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "LianDepthSample.hlsl"
            #include "LianShared.hlsl"

            float4 _LianDoFCoCParams;    // _18._m0: xz=近/远斜率, yw=近/远截距
            float _LianDoFSkyFallback;   // _18._m1: 天空回退距离
            float _LianDoFIntensity;     // _18._m2: 强度
            float _LianDoFCurveExponent; // _18._m3: 近焦曲线指数
            float _LianDoFDim;           // _18._m4: rgb 调暗
            float2 _LianScreenSize;      // _15._m10.xy: 全分辨率像素尺寸

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float depth = LianSampleSceneDepth(uv);

                // 世界重建 + viewLen(dump 线 3752-3768)
                float3 worldPos = ComputeWorldSpacePosition(uv, depth, unity_MatrixInvVP);
                float viewLen = length(_WorldSpaceCameraPos.xyz - worldPos);
                bool isSky = UNITY_REVERSED_Z ? (depth == 0.0) : (depth == 1.0);
                viewLen = isSky ? _LianDoFSkyFallback : viewLen;

                // 对焦曲线(dump 线 3769-3777)
                float2 distToFocus = viewLen * _LianDoFCoCParams.xz + _LianDoFCoCParams.yw;
                float2 farNearFocus = clamp(distToFocus, 0.0, 1.0);
                float nearCurve = pow(farNearFocus.y, _LianDoFCurveExponent);
                float cocFactor = (farNearFocus.y < farNearFocus.x) ? farNearFocus.x : -nearCurve;

                // sceneColor(dump 线 3778-3786)
                half4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);
                cocFactor = (sceneColor.a < 0.001000000047497451305389404296875) ? 0.0 : cocFactor;
                float cocRadius = cocFactor * _LianDoFIntensity * _LianScreenSize.x * 0.5;
                float3 dimmed = sceneColor.rgb * _LianDoFDim;
                float3 color = lerp(sceneColor.rgb, dimmed, cocFactor == 0.0 ? 1.0 : 0.0);
                return half4(max(color, 0.0), cocRadius);
            }
            ENDHLSL
        }
    }
}
