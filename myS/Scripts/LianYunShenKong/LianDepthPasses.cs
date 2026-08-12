using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// 深度拷贝(AfterRenderingOpaques):把相机深度(地面 opaque + 角色 pre-pass 深度)
    /// 用 URP CopyDepth 材质拷进自己的 R32F RT,并绑定 _CameraDepthTexture 全局,
    /// 供 pass 6-19 采样。URP 自带的 CopyDepthPass 在本 fork 上未分配 RT(全局为空),
    /// 因此本链自持深度拷贝。
    /// </summary>
    public class LianDepthCopyPass : ScriptableRenderPass
    {
        RTHandle m_DepthCopyRT;
        RTHandle m_ChainDepthRT;    // 由 feature 注入的链内深度(pre-pass 输出)
        Material m_CopyMaterial;

        public RTHandle output => m_DepthCopyRT;

        public RTHandle chainDepthRT
        {
            get => m_ChainDepthRT;
            set => m_ChainDepthRT = value;
        }

        public LianDepthCopyPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianDepthCopyPass));
            m_CopyMaterial = CreateMaterial("Hidden/Universal Render Pipeline/CopyDepth");
            // Normal 输入强制 fork 的 DepthNormalPrepass 运行:m_DepthTexture 由 fork
            // 自绘(地面深度正确),而不是依赖链内 DepthOnly 重绘。
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        static Material CreateMaterial(string shaderName)
        {
            Shader shader = Shader.Find(shaderName);
            if (shader == null)
                return null;
            return new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R32_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_DepthCopyRT, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.CameraDepthCopyName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_CopyMaterial == null || m_DepthCopyRT == null)
                return;

            // 源 = 相机深度(opaque 已绘制地面 0.41 + 角色 0.72,深度测试/写入均正确)
            RTHandle cameraDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            if (cameraDepth == null || cameraDepth.rt == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianDepthCopy");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalTexture("_CameraDepthAttachment", cameraDepth);
                Blitter.BlitCameraTexture(cmd, cameraDepth, m_DepthCopyRT, m_CopyMaterial, 0);
                cmd.SetGlobalTexture("_CameraDepthTexture", m_DepthCopyRT);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    /// <summary>
    /// 深度链:pass 8 线性深度(_LianLinearDepthTex + _LianHalfResDepth)、
    /// pass 10 半分辨率深度 gather(_LianHalfResDepth)、pass 9 SSAO+blur(_LianSSAOTex, Phase 3)。
    /// </summary>
    public class LianDepthLinearPass : ScriptableRenderPass
    {
        RTHandle m_LinearRT;
        RTHandle m_HalfDepthRT;
        Material m_Material;

        public RTHandle linearRT => m_LinearRT;
        public RTHandle halfDepthRT => m_HalfDepthRT;

        public LianDepthLinearPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianDepthLinearPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/DepthLinear");
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        RTHandle m_SharedDepthRT;
        public RTHandle sharedDepthRT { get => m_SharedDepthRT; set => m_SharedDepthRT = value; }

        internal static Material CreateMaterial(string shaderName)
        {
            Shader shader = Shader.Find(shaderName);
            if (shader == null)
                return null;
            return new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.graphicsFormat = GraphicsFormat.R16G16_SFloat;
            desc.depthBufferBits = 0;
            desc.depthStencilFormat = GraphicsFormat.None;
            RenderingUtils.ReAllocateIfNeeded(ref m_LinearRT, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.LinearDepthTexName);

            var depthDesc = renderingData.cameraData.cameraTargetDescriptor;
            depthDesc.width = Mathf.Max(1, depthDesc.width / 2);
            depthDesc.height = Mathf.Max(1, depthDesc.height / 2);
            depthDesc.msaaSamples = 1;
            depthDesc.graphicsFormat = GraphicsFormat.None;
            depthDesc.depthBufferBits = 24;
            depthDesc.depthStencilFormat = GraphicsFormat.D24_UNorm_S8_UInt;
            RenderingUtils.ReAllocateIfNeeded(ref m_HalfDepthRT, depthDesc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.HalfResDepthName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_LinearRT == null || m_HalfDepthRT == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianDepthLinear");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                CoreUtils.SetRenderTarget(cmd, m_LinearRT, m_HalfDepthRT, ClearFlag.DepthStencil, Color.clear);
                // 深度来自共享拷贝 RT:全局 + 材质双绑定(绕开 fork 全局量失效问题)
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                {
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);
                    if (m_Material != null)
                        m_Material.SetTexture("_CameraDepthTexture", m_SharedDepthRT.rt);
                }
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianHalfDepthPass : ScriptableRenderPass
    {
        RTHandle m_HalfDepthRT;
        Material m_Material;

        public LianHalfDepthPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianHalfDepthPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/HalfDepth");
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        RTHandle m_SharedDepthRT;
        public RTHandle sharedDepthRT { get => m_SharedDepthRT; set => m_SharedDepthRT = value; }

        static Material CreateMaterial(string shaderName)
        {
            Shader shader = Shader.Find(shaderName);
            if (shader == null)
                return null;
            return new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var depthDesc = renderingData.cameraData.cameraTargetDescriptor;
            depthDesc.width = Mathf.Max(1, depthDesc.width / 2);
            depthDesc.height = Mathf.Max(1, depthDesc.height / 2);
            depthDesc.msaaSamples = 1;
            depthDesc.graphicsFormat = GraphicsFormat.None;
            depthDesc.depthBufferBits = 24;
            depthDesc.depthStencilFormat = GraphicsFormat.D24_UNorm_S8_UInt;
            RenderingUtils.ReAllocateIfNeeded(ref m_HalfDepthRT, depthDesc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.HalfResDepthName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_HalfDepthRT == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianHalfDepth");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // _CameraDepthTexture 由 URP CopyDepthPass 提供

                // 仅深度目标
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                {
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);
                    if (m_Material != null)
                        m_Material.SetTexture("_CameraDepthTexture", m_SharedDepthRT.rt);
                }
                cmd.SetRenderTarget(BuiltinRenderTextureType.None, m_HalfDepthRT.nameID);
                cmd.ClearRenderTarget(true, false, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianSSAOPass : ScriptableRenderPass
    {
        RTHandle m_Output;   // _LianSSAOTex
        RTHandle m_TempRT;
        Material m_SSAOMaterial;
        Material m_BlurMaterial;

        public RTHandle output => m_Output;

        public float baseRadius = 0.25f;
        public float angleBias = 0.2f;
        public float distScale = -0.01f;
        public float strength = 0.5f;

        public LianSSAOPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianSSAOPass));
            m_SSAOMaterial = CreateMaterial("Hidden/LianYunShenKong/SSAO");
            m_BlurMaterial = CreateMaterial("Hidden/LianYunShenKong/SSAOBlur");
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        RTHandle m_SharedDepthRT;
        public RTHandle sharedDepthRT { get => m_SharedDepthRT; set => m_SharedDepthRT = value; }

        static Material CreateMaterial(string shaderName)
        {
            Shader shader = Shader.Find(shaderName);
            if (shader == null)
                return null;
            return new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.SSAOTexName);
            RenderingUtils.ReAllocateIfNeeded(ref m_TempRT, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_LianSSAOTemp");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_SSAOMaterial == null || m_Output == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth);
            int h = Mathf.Max(1, cameraData.camera.pixelHeight);

            CommandBuffer cmd = CommandBufferPool.Get("LianSSAOPass");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // _CameraDepthTexture 由 URP CopyDepthPass 提供

                // dump `_14` 参数
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                {
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);
                    if (m_SSAOMaterial != null)
                        m_SSAOMaterial.SetTexture("_CameraDepthTexture", m_SharedDepthRT.rt);
                }
                cmd.SetGlobalVector("_LianSSAOTexelSize", new Vector4(1f / w, 1f / h, 2f / w, 2f / h));
                cmd.SetGlobalVector("_LianSSAOParams", new Vector4(0f, baseRadius, angleBias, distScale));
                cmd.SetGlobalFloat("_LianSSAOStrength", strength);

                // SSAO → 临时 RT
                CoreUtils.SetRenderTarget(cmd, m_TempRT, ClearFlag.Color, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_SSAOMaterial, 0, MeshTopology.Triangles, 3);

                // 十字模糊 → 输出
                cmd.SetGlobalTexture("_BlitTexture", m_TempRT);
                cmd.SetGlobalVector("_LianSSAOBlurTexelSize", new Vector4(1f / (w / 2), 1f / (h / 2), 0f, 0f));
                cmd.SetGlobalTexture(LianFrameData.SSAOTexName, m_Output);
                CoreUtils.SetRenderTarget(cmd, m_Output, ClearFlag.Color, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_BlurMaterial, 0, MeshTopology.Triangles, 3);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
