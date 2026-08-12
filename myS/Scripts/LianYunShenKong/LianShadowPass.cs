using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace LianYunShenKong
{
    /// <summary>
    /// pass 3/4:级联(0-2)+ 特殊光(第 4 张)shadow map 渲染到 _LianShadowAtlasTex
    /// (R32F Texture2DArray 4×2048²)。每切片 SetViewProjectionMatrices 后 DrawRenderers,
    /// 统一用 LianShadowCaster.shader 的 override 材质(自定义 bias + alpha 变体)。
    /// </summary>
    public class LianShadowPass : ScriptableRenderPass
    {
        static readonly ShaderTagId k_LianShadowCasterTag = new ShaderTagId("LianShadowCaster");

        RTHandle m_ShadowAtlasRT;
        RTHandle m_SliceDepthRT;
        Material m_OverrideMaterial;

        public RTHandle shadowAtlas => m_ShadowAtlasRT;

        public LianCascadeData cascadeData;
        public bool hasSpecialShadow;
        public Vector3 lightDirection = Vector3.up;
        public float depthBias = 0.005f;
        public float normalBias = 1.0f;
        public int shadowMapSize = LianFrameData.ShadowMapSize;

        public LianShadowPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianShadowPass));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (m_OverrideMaterial == null)
            {
                Shader shader = Shader.Find("Hidden/LianYunShenKong/ShadowCaster");
                if (shader != null)
                    m_OverrideMaterial = new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
            }

            var atlasDesc = new RenderTextureDescriptor(shadowMapSize, shadowMapSize, RenderTextureFormat.RFloat, 0)
            {
                dimension = TextureDimension.Tex2DArray,
                volumeDepth = LianFrameData.ShadowAtlasSlices,
                msaaSamples = 1,
            };
            RenderingUtils.ReAllocateIfNeeded(ref m_ShadowAtlasRT, atlasDesc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.ShadowAtlasTexName);

            var depthDesc = new RenderTextureDescriptor(shadowMapSize, shadowMapSize, RenderTextureFormat.Depth, 24)
            {
                msaaSamples = 1,
            };
            RenderingUtils.ReAllocateIfNeeded(ref m_SliceDepthRT, depthDesc, FilterMode.Point, TextureWrapMode.Clamp, name: "_LianShadowSliceDepth");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_OverrideMaterial == null || m_ShadowAtlasRT == null || m_SliceDepthRT == null)
            {
                return;
            }
            var camera = renderingData.cameraData.camera;
            if (camera == null)
                return;

            string ovrName = m_OverrideMaterial != null && m_OverrideMaterial.shader != null ? m_OverrideMaterial.shader.name : "null";
            if (cascadeData.view != null)
            {
                var v = cascadeData.view[0];
                var p = cascadeData.proj[0];
            }

            CommandBuffer cmd = CommandBufferPool.Get("LianShadowPass");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // 自定义 bias(dump `_37._m0` 布局 = _ShadowBias)x=depth, y=normal
                cmd.SetGlobalVector("_ShadowBias", new Vector4(depthBias, normalBias, 0f, 0f));
                cmd.SetGlobalVector("_LightDirection", new Vector4(lightDirection.x, lightDirection.y, lightDirection.z, 0f));

                var settings = CreateDrawingSettings(k_LianShadowCasterTag, ref renderingData, SortingCriteria.CommonOpaque);
                settings.overrideMaterial = null;   // 测试:角色自带 LianShadowCaster pass
                var filter = new FilteringSettings(RenderQueueRange.opaque, ~0);

                int sliceCount = hasSpecialShadow ? 4 : 3;
                // 测试:先用相机矩阵画一次(验证 RT 绑定与 DrawRenderers)
                {
                    cmd.SetRenderTarget(m_ShadowAtlasRT.nameID, m_SliceDepthRT.nameID);
                    cmd.ClearRenderTarget(true, false, Color.clear);
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    context.DrawRenderers(renderingData.cullResults, ref settings, ref filter);
                }
                for (int i = 0; i < sliceCount; ++i)
                {
                    // 5 参重载(含 depthSlice)在本 fork 可能不可靠,先测 2 参(默认切片 0)
                    cmd.SetRenderTarget(m_ShadowAtlasRT.nameID, m_SliceDepthRT.nameID);
                    cmd.ClearRenderTarget(true, false, Color.clear);
                    cmd.SetViewProjectionMatrices(cascadeData.view[i], cascadeData.proj[i]);
                    // flush 目标/矩阵(矩阵设置必须在绘制前生效,DrawRenderers 即时执行)
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    context.DrawRenderers(renderingData.cullResults, ref settings, ref filter);
                }

                // 供 pass 6/13 采样
                cmd.SetGlobalTexture(LianFrameData.ShadowAtlasTexName, m_ShadowAtlasRT);

                // 恢复相机矩阵,后续 pass 按相机渲染
                cmd.SetViewProjectionMatrices(camera.worldToCameraMatrix,
                    GL.GetGPUProjectionMatrix(camera.projectionMatrix, true));
                context.ExecuteCommandBuffer(cmd);
            }
            CommandBufferPool.Release(cmd);
        }
    }
}
