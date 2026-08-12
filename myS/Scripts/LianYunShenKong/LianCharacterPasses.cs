using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// 角色绘制:pass 16 skin diffuse MRT(_LianSkinDiffuseTex + _LianSkinProfileTex + 刷新 _LianHalfResDepth)、
    /// pass 20 render object(角色最终着色写 _CameraColorTexture,深度测试 _CameraDepthTexture)。
    /// </summary>
    public class LianSkinDiffusePass : ScriptableRenderPass
    {
        static readonly ShaderTagId k_LianSkinTag = new ShaderTagId("LianSkin");

        RTHandle m_DiffuseRT;
        RTHandle m_ProfileRT;

        public RTHandle output => m_DiffuseRT;
        public RTHandle diffuseRT => m_DiffuseRT;
        public RTHandle profileRT => m_ProfileRT;

        public LayerMask characterLayerMask = ~0;
        public RTHandle halfDepthRT;
        public Vector3 mainLightDir = Vector3.up;
        public Vector4 tileGridParams;

        public LianSkinDiffusePass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianSkinDiffusePass));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_DiffuseRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.SkinDiffuseTexName);

            desc.graphicsFormat = GraphicsFormat.R8_UNorm;
            RenderingUtils.ReAllocateIfNeeded(ref m_ProfileRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.SkinProfileTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_DiffuseRT == null || m_ProfileRT == null || halfDepthRT == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianSkinDiffuse");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                LianCharacterPassesUtils.BindFrameGlobals(cmd, mainLightDir, tileGridParams);
                cmd.SetGlobalTexture(LianFrameData.SkinDiffuseTexName, m_DiffuseRT);
                cmd.SetGlobalTexture(LianFrameData.SkinProfileTexName, m_ProfileRT);

                cmd.SetRenderTarget(
                    new RenderTargetIdentifier[] { m_DiffuseRT.nameID, m_ProfileRT.nameID },
                    halfDepthRT.nameID);
                cmd.ClearRenderTarget(true, true, Color.clear);
                // flush 目标/清除(DrawRenderers 即时执行)
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var settings = CreateDrawingSettings(k_LianSkinTag, ref renderingData, SortingCriteria.CommonOpaque);
                var filter = new FilteringSettings(RenderQueueRange.opaque, characterLayerMask);
                context.DrawRenderers(renderingData.cullResults, ref settings, ref filter);
            }
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianRenderObjectPass : ScriptableRenderPass
    {
        static readonly ShaderTagId k_LianCharacterTag = new ShaderTagId("LianCharacter");

        public RTHandle output => null;   // 直接写 _CameraColorTexture

        public LayerMask characterLayerMask = ~0;
        public Vector3 mainLightDir = Vector3.up;
        public Vector4 tileGridParams;
        public Texture3D fogLUT3D;
        RTHandle m_SharedDepthRT;

        public RTHandle sharedDepthRT
        {
            get => m_SharedDepthRT;
            set => m_SharedDepthRT = value;
        }

        public LianRenderObjectPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianRenderObjectPass));
            // 角色着色采样 _CameraDepthTexture:由共享深度拷贝 RT 提供(含角色自身深度)
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cameraData = renderingData.cameraData;
            var renderer = cameraData.renderer;
            RTHandle color = renderer.cameraColorTargetHandle;
            RTHandle depth = renderer.cameraDepthTargetHandle;
            if (color == null || color.rt == null || depth == null || depth.rt == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianRenderObject");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                LianCharacterPassesUtils.BindFrameGlobals(cmd, mainLightDir, tileGridParams);
                if (fogLUT3D != null)
                    cmd.SetGlobalTexture("_FogLUT3D", fogLUT3D);

                // 目标 = 相机颜色 + 相机深度(ZTest LessEqual 见 shader)
                cmd.SetRenderTarget(color.nameID, depth.nameID);
                // flush 目标(绘制前生效)
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var settings = CreateDrawingSettings(k_LianCharacterTag, ref renderingData, SortingCriteria.CommonOpaque);
                var filter = new FilteringSettings(RenderQueueRange.opaque, characterLayerMask);
                context.DrawRenderers(renderingData.cullResults, ref settings, ref filter);
            }
            CommandBufferPool.Release(cmd);
        }
    }

    /// <summary>角色材质帧级全局(dump `_14` 块):主光方向 / tile 网格 / alpha 混合 / mip bias。</summary>
    public static class LianCharacterPassesUtils
    {
        public static void BindFrameGlobals(CommandBuffer cmd, Vector3 mainLightDir, Vector4 tileGridParams)
        {
            cmd.SetGlobalVector("_MainLightDir", new Vector4(mainLightDir.x, mainLightDir.y, mainLightDir.z, 0f));
            cmd.SetGlobalVector("_LianTileGridParams", tileGridParams);
            cmd.SetGlobalFloat("_AlphaMix", 0f);
            cmd.SetGlobalFloat("_TextureMipBias", 0f);
        }
    }
}
