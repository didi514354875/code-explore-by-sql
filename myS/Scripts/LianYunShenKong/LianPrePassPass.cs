using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// pass 5:角色 MRT 重绘 — _LianMotionVectorTex(SV_Target0)+ _LianNormalTex(SV_Target1)+ 相机深度。
    /// LightMode = LianPrePass,VS/PS 见 LianCharacter.shader 的 LianPrePass pass(dump `_43`)。
    /// 本链在 URP opaque pass 之前执行,故先用 DepthOnly 标签补齐全场景深度,供 pass 6-19 采样。
    /// </summary>
    public class LianPrePassPass : ScriptableRenderPass
    {
        static readonly ShaderTagId k_LianPrePassTag = new ShaderTagId("LianPrePass");
        static readonly ShaderTagId k_DepthOnlyTag = new ShaderTagId("DepthOnly");

        RTHandle m_MotionRT;
        RTHandle m_NormalRT;
        RTHandle m_ChainDepthRT;    // 链内自持全分辨率深度(地面+角色),供 depth copy 采样
        Material m_DepthOverrideMat; // 地面深度 override(DepthGround: Cull Off + ZTest Always)
        Matrix4x4 m_PrevViewProj;

        public RTHandle motionRT => m_MotionRT;
        public RTHandle normalRT => m_NormalRT;
        public RTHandle chainDepthRT => m_ChainDepthRT;

        public Material depthOverrideMaterial
        {
            get => m_DepthOverrideMat;
            set => m_DepthOverrideMat = value;
        }

        public LayerMask characterLayerMask = ~0;

        public LianPrePassPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianPrePassPass));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R8G8B8A8_UNorm;
            RenderingUtils.ReAllocateIfNeeded(ref m_MotionRT, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.MotionVectorTexName);
            RenderingUtils.ReAllocateIfNeeded(ref m_NormalRT, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.NormalTexName);

            var depthDesc = renderingData.cameraData.cameraTargetDescriptor;
            depthDesc.msaaSamples = 1;
            depthDesc.graphicsFormat = GraphicsFormat.None;
            depthDesc.depthBufferBits = 24;
            depthDesc.depthStencilFormat = GraphicsFormat.D24_UNorm_S8_UInt;
            RenderingUtils.ReAllocateIfNeeded(ref m_ChainDepthRT, depthDesc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.ChainDepthName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var camera = renderingData.cameraData.camera;
            if (camera == null || m_MotionRT == null || m_NormalRT == null)
                return;

            var globalDepth = Shader.GetGlobalTexture("_CameraDepthTexture");

            CommandBuffer cmd = CommandBufferPool.Get("LianPrePass");
            // 帧级矩阵(dump `_17._m0` prev / `_17._m2` nonjitter),URP 只在自带运动矢量
            // pass 中设置,这里每帧主动绑定
            Matrix4x4 nonJitteredVP = camera.nonJitteredProjectionMatrix * camera.worldToCameraMatrix;
            Matrix4x4 curVP = GL.GetGPUProjectionMatrix(camera.projectionMatrix, true) * camera.worldToCameraMatrix;
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalMatrix("_NonJitteredViewProjMatrix", nonJitteredVP);
                cmd.SetGlobalMatrix("_PrevViewProjMatrix", m_PrevViewProj);
                // fork 的 unity_MatrixInvVP 未正确设置(世界重建恒为 0),用非抖动 VP 的逆代替
                cmd.SetGlobalMatrix("unity_MatrixInvVP", nonJitteredVP.inverse);
                // dump `_12._m14.x` > 0 分支:启用上一帧 OS 位置
                cmd.SetGlobalVector("unity_MotionVectorsParams", new Vector4(1f, 0f, 0f, 0f));

                // MRT:颜色 0 = 运动矢量, 颜色 1 = 法线;深度 = 链内自持深度(dump pass 5)。
                // 深度显式清到远平面(0.0,reversed-z),避免默认清除值拒绝地面写入。
                cmd.SetRenderTarget(
                    new RenderTargetIdentifier[] { m_MotionRT.nameID, m_NormalRT.nameID },
                    m_ChainDepthRT.nameID);
                cmd.ClearRenderTarget(true, true, Color.clear);
                // 先 flush:目标设置与清除必须早于 DrawRenderers(即时执行)
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                // 1) 全场景不透明深度,补进链内深度。
                //    overrideMaterial = DepthGround(Cull Off + ZTest Always + 标准 VP):
                //    平面地面的背面/深度测试在 fork 上写出错误深度(0/1.0),双面无条件写入解决。
                var depthOnlySettings = CreateDrawingSettings(k_DepthOnlyTag, ref renderingData, SortingCriteria.CommonOpaque);
                if (m_DepthOverrideMat != null)
                    depthOnlySettings.overrideMaterial = m_DepthOverrideMat;
                var depthFilter = new FilteringSettings(RenderQueueRange.opaque, ~0);
                context.DrawRenderers(renderingData.cullResults, ref depthOnlySettings, ref depthFilter);

                // 2) 角色 MRT(深度写入相机深度)
                var prePassSettings = CreateDrawingSettings(k_LianPrePassTag, ref renderingData, SortingCriteria.CommonOpaque);
                var characterFilter = new FilteringSettings(RenderQueueRange.opaque, characterLayerMask);
                context.DrawRenderers(renderingData.cullResults, ref prePassSettings, ref characterFilter);

                // 供 pass 7/9/16/20 采样
                cmd.SetGlobalTexture(LianFrameData.NormalTexName, m_NormalRT);
                cmd.SetGlobalTexture(LianFrameData.MotionVectorTexName, m_MotionRT);
                context.ExecuteCommandBuffer(cmd);
            }
            CommandBufferPool.Release(cmd);

            m_PrevViewProj = nonJitteredVP;
        }
    }
}
