using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// 全屏 blit 基类:封装 core 包 Blitter.BlitCameraTexture(cmd, src, dst, Material, pass)。
    /// 子类在 Execute 里绑定材质参数后调用 Blit()。
    /// </summary>
    public abstract class LianFullscreenPass : ScriptableRenderPass
    {
        protected Material m_Material;
        protected int m_PassIndex;

        protected LianFullscreenPass(Material material, int passIndex)
        {
            m_Material = material;
            m_PassIndex = passIndex;
        }

        /// <summary>子类 Execute 用:把 m_Material 的 m_PassIndex 号 pass 画到 destination。</summary>
        protected void Blit(CommandBuffer cmd, RTHandle source, RTHandle destination)
        {
            if (m_Material == null || source == null || destination == null)
                return;
            Blitter.BlitCameraTexture(cmd, source, destination, m_Material, m_PassIndex);
        }
    }

    /// <summary>
    /// pass 1:程序化雾 noise,渲染到 _LianFogNoiseTex(dump `_53`)。
    /// 材质由 feature 的 _fogNoiseMaterial 提供,每帧刷新引用。
    /// </summary>
    public class LianFogNoisePass : LianFullscreenPass
    {
        RTHandle m_Output;

        public RTHandle output => m_Output;
        public Material material
        {
            get => m_Material;
            set => m_Material = value;
        }

        public LianFogNoisePass(Material material) : base(material, 0)
        {
            profilingSampler = new ProfilingSampler(nameof(LianFogNoisePass));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R8G8B8A8_UNorm;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.FogNoiseTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianFogNoise");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                RTHandle src = renderingData.cameraData.renderer.cameraColorTargetHandle;
                Blit(cmd, src, m_Output);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
