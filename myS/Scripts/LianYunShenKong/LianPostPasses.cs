using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// 后处理链(pass 21-24):21 CoC(_LianDoFBufferTex)→ 21b 预过滤(_LianDoFHalfTex)→
    /// 22 TAA(历史乒乓 _LianTAAHistoryTex/_LianTAAHistoryPrevTex)→ 23 DOF(_LianDoFResultTex)→
    /// 24 合并回 _CameraColorTexture(Blend One SrcAlpha)。
    /// </summary>
    public class LianDoFCoCPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        Material m_Material;

        public RTHandle output => m_Output;

        public float focusDistance = 6f;
        public float focusRange = 12f;
        public float intensity = 1f;
        public float curveExponent = 1f;
        public float dim = 1f;
        public float skyFallback = 1000f;

        public LianDoFCoCPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianDoFCoCPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/DoFCoC");
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
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.DoFBufferTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth);

            CommandBuffer cmd = CommandBufferPool.Get("LianDoFCoC");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // 对焦曲线:nearFocus = (viewLen·scale + bias) ∈ [0,1]
                float invRange = 1f / Mathf.Max(focusRange, 0.01f);
                cmd.SetGlobalVector("_LianDoFCoCParams", new Vector4(
                    invRange, -(focusDistance - focusRange * 0.5f) * invRange,
                    invRange, -(focusDistance + focusRange * 0.5f) * invRange));
                cmd.SetGlobalFloat("_LianDoFSkyFallback", skyFallback);
                cmd.SetGlobalFloat("_LianDoFIntensity", intensity);
                cmd.SetGlobalFloat("_LianDoFCurveExponent", curveExponent);
                cmd.SetGlobalFloat("_LianDoFDim", dim);
                cmd.SetGlobalVector("_LianScreenSize", new Vector4(w, cameraData.camera.pixelHeight, 0f, 0f));

                // _CameraDepthTexture 由 URP CopyDepthPass 提供
                cmd.SetGlobalTexture(LianFrameData.DoFBufferTexName, m_Output);
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);

                RTHandle source = cameraData.renderer.cameraColorTargetHandle;
                Blitter.BlitCameraTexture(cmd, source, m_Output, m_Material, 0);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianDoFPrefilterPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        Material m_Material;

        public RTHandle output => m_Output;

        /// <summary>输入 = pass 21 输出(_LianDoFBufferTex),由 feature 注入</summary>
        public RTHandle source;

        public LianDoFPrefilterPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianDoFPrefilterPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/DoFPrefilter");
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
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.DoFHalfTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null || source == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth);
            int h = Mathf.Max(1, cameraData.camera.pixelHeight);

            CommandBuffer cmd = CommandBufferPool.Get("LianDoFPrefilter");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalVector("_LianDoFPrefilterTexelSize", new Vector4(1f / w, 1f / h, 0f, 0f));
                cmd.SetGlobalVector("_LianDoFPrefilterMaxUV", new Vector4(1f, 1f, 0f, 0f));
                cmd.SetGlobalTexture(LianFrameData.DoFHalfTexName, m_Output);

                // 输入 = pass 21 输出(_BlitTexture 由 Blitter 绑定)
                Blitter.BlitCameraTexture(cmd, source, m_Output, m_Material, 0);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianTAAPass : ScriptableRenderPass
    {
        RTHandle m_HistoryRT;
        RTHandle m_HistoryPrevRT;
        Material m_Material;

        public RTHandle output => m_HistoryRT;

        public float boxExpand = 0.0f;
        public float useCustomRange = 0.0f;

        public LianTAAPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianTAAPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/TAA");
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
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_HistoryRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.TAAHistoryTexName);
            RenderingUtils.ReAllocateIfNeeded(ref m_HistoryPrevRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.TAAHistoryPrevTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_HistoryRT == null || m_HistoryPrevRT == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth / 2);
            int h = Mathf.Max(1, cameraData.camera.pixelHeight / 2);

            CommandBuffer cmd = CommandBufferPool.Get("LianTAA");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalVector("_LianTAATexelSize", new Vector4(1f / w, 1f / h, w, h));
                // 5 tap 权重(up/down/left/right;中心 = 1-Σ)
                cmd.SetGlobalVector("_LianTAA5TapWeights", new Vector4(0.2f, 0.2f, 0.2f, 0.2f));
                cmd.SetGlobalFloat("_LianTAABoxExpand", boxExpand);
                cmd.SetGlobalFloat("_LianTAAUseCustomRange", useCustomRange);

                // 上一帧历史 = 乒乓的另一端(首帧为清 0 RT)
                cmd.SetGlobalTexture(LianFrameData.TAAHistoryPrevTexName, m_HistoryPrevRT);
                cmd.SetGlobalTexture(LianFrameData.TAAHistoryTexName, m_HistoryRT);

                // 输出到当前历史;完成后交换
                CoreUtils.SetRenderTarget(cmd, m_HistoryRT, ClearFlag.Color, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3);

                (m_HistoryRT, m_HistoryPrevRT) = (m_HistoryPrevRT, m_HistoryRT);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianDoFPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        Material m_Material;

        public RTHandle output => m_Output;

        /// <summary>输入 = pass 21b 输出(_LianDoFHalfTex),由 feature 注入</summary>
        public RTHandle source;

        public float minBlurRadius = 4f;
        public float radiusMult = 1f;
        public float cocOffset = 1f;
        public float aspect = 1f;

        public LianDoFPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianDoFPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/DoF");
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
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.DoFResultTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null || source == null)
                return;

            var cameraData = renderingData.cameraData;
            float aspectValue = aspect;
            if (aspectValue <= 0f)
                aspectValue = (float)cameraData.camera.pixelWidth / Mathf.Max(cameraData.camera.pixelHeight, 1);

            CommandBuffer cmd = CommandBufferPool.Get("LianDoF");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalVector("_LianDoFParams",
                    new Vector4(minBlurRadius, radiusMult, cocOffset, aspectValue));
                cmd.SetGlobalTexture(LianFrameData.DoFResultTexName, m_Output);

                // pass 1 = 远近 gather(dump `_85`);输入 = 21b 输出(_BlitTexture 由 Blitter 绑定)
                Blitter.BlitCameraTexture(cmd, source, m_Output, m_Material, 1);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianDoFMergePass : ScriptableRenderPass
    {
        Material m_Material;

        /// <summary>输入 = pass 23 输出(_LianDoFResultTex),由 feature 注入</summary>
        public RTHandle source;

        public LianDoFMergePass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianDoFMergePass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/DoFMerge");
        }

        static Material CreateMaterial(string shaderName)
        {
            Shader shader = Shader.Find(shaderName);
            if (shader == null)
                return null;
            return new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || source == null)
                return;

            var cameraData = renderingData.cameraData;
            RTHandle color = cameraData.renderer.cameraColorTargetHandle;
            if (color == null || color.rt == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianDoFMerge");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // 合并 DoF 结果 → 相机颜色(Blend One SrcAlpha)
                Blitter.BlitCameraTexture(cmd, source, color, m_Material, 0);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
