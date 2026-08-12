using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// pass 6:1/4 分辨率级联阴影 → 屏幕空间 _LianCascadeShadowTex(R16F)。
    /// PS 见 LianCascadeShadow.shader(dump `_96`),采样 _LianShadowAtlasTex + 相机深度。
    /// </summary>
    public class LianShadowScreenPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        Material m_Material;
        RTHandle m_SharedDepthRT;   // 由 feature 注入的 _LianCameraDepthCopy(深度拷贝 pass 输出)

        public RTHandle output => m_Output;

        public RTHandle sharedDepthRT
        {
            get => m_SharedDepthRT;
            set => m_SharedDepthRT = value;
        }

        public LianShadowScreenPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianShadowScreenPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/CascadeShadow");
            // 声明需要深度:URP 在 AfterRenderingOpaques 用 CopyDepthPass 填充 _CameraDepthTexture
            ConfigureInput(ScriptableRenderPassInput.Depth);
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
            desc.width = Mathf.Max(1, desc.width / 4);
            desc.height = Mathf.Max(1, desc.height / 4);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.CascadeShadowTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianShadowScreenPass");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                var cameraData = renderingData.cameraData;
                int w = Mathf.Max(1, cameraData.camera.pixelWidth);
                int h = Mathf.Max(1, cameraData.camera.pixelHeight);
                cmd.SetGlobalVector("_LianCascadeMaskSize", new Vector2(w / 4f, h / 4f));
                cmd.SetGlobalVector("_LianCameraDepthTexelSize", new Vector4(1f / w, 1f / h, 0f, 0f));

                // 直接绑定共享深度拷贝 RT(绕开可能被重置的全局)
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                {
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);
                    m_Material.SetTexture("_CameraDepthTexture", m_SharedDepthRT.rt);
                }

                cmd.SetGlobalTexture(LianFrameData.CascadeShadowTexName, m_Output);
                CoreUtils.SetRenderTarget(cmd, m_Output, ClearFlag.Color, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
