using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// 计算 shader 调度:pass 2 tile 灯光剔除 + pass 7 capsule AO。
    /// </summary>
    public class LianTileLightCullingPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        ComputeShader m_Shader;
        int m_Kernel = -1;

        public RTHandle output => m_Output;

        public ComputeShader computeShader
        {
            get => m_Shader;
            set
            {
                m_Shader = value;
                m_Kernel = value != null ? value.FindKernel("TileLightCulling") : -1;
            }
        }

        public int gridSize = 128;
        public Vector2 gridOrigin;
        public float tileWorldSize = 4f;

        public LianTileLightCullingPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianTileLightCullingPass));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = new RenderTextureDescriptor(gridSize, gridSize, RenderTextureFormat.ARGBFloat, 0)
            {
                msaaSamples = 1,
                enableRandomWrite = true,
            };
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.TileLightIndexTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Shader == null || m_Output == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianTileLightCulling");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetComputeVectorParam(m_Shader, "_LianTileScaleBias",
                    new Vector4(gridOrigin.x, gridOrigin.y, tileWorldSize, tileWorldSize));
                cmd.SetComputeTextureParam(m_Shader, m_Kernel, "_LianTileLightIndexTex", m_Output);
                cmd.SetGlobalTexture(LianFrameData.TileLightIndexTexName, m_Output);
                cmd.DispatchCompute(m_Shader, m_Kernel, Mathf.Max(1, gridSize / 8), Mathf.Max(1, gridSize / 8), 1);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public class LianCapsuleAOPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        ComputeShader m_Shader;
        int m_Kernel = -1;

        public RTHandle output => m_Output;

        public ComputeShader computeShader
        {
            get => m_Shader;
            set
            {
                m_Shader = value;
                m_Kernel = value != null ? value.FindKernel("CapsuleAO") : -1;
            }
        }

        public int capsuleCount;
        public float errorRadius = 0.25f;
        public float normDist = 200f;
        public float aoPow = 1f;
        public float coneAngle = 0.5f;
        public Vector2 normalYOffsetScale = Vector2.zero;
        public float normalYFactor = 0f;

        public LianCapsuleAOPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianCapsuleAOPass));
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        RTHandle m_SharedDepthRT;
        public RTHandle sharedDepthRT { get => m_SharedDepthRT; set => m_SharedDepthRT = value; }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.width = Mathf.Max(1, desc.width / 2);
            desc.height = Mathf.Max(1, desc.height / 2);
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            desc.enableRandomWrite = true;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.CapsuleAOTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Shader == null || m_Output == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth);
            int h = Mathf.Max(1, cameraData.camera.pixelHeight);

            CommandBuffer cmd = CommandBufferPool.Get("LianCapsuleAO");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // _CameraDepthTexture 由 URP CopyDepthPass 提供(本 pass 声明 Depth 输入)
                cmd.SetComputeIntParam(m_Shader, "_LianCapsuleAOCount", capsuleCount);
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);
                cmd.SetComputeFloatParam(m_Shader, "_LianCapsuleAOErrorRadius", errorRadius);
                cmd.SetComputeFloatParam(m_Shader, "_LianCapsuleAONormDist", normDist);
                cmd.SetComputeFloatParam(m_Shader, "_LianCapsuleAOPow", aoPow);
                cmd.SetComputeFloatParam(m_Shader, "_LianCapsuleAOConeAngle", coneAngle);
                cmd.SetComputeFloatParam(m_Shader, "_LianCapsuleAOUvScale", 2f);
                cmd.SetComputeVectorParam(m_Shader, "_LianCapsuleAONormalY", normalYOffsetScale);
                cmd.SetComputeFloatParam(m_Shader, "_LianCapsuleAONormalYFactor", normalYFactor);
                cmd.SetComputeVectorParam(m_Shader, "_LianCapsuleAOTexelSize", new Vector4(1f / w, 1f / h, 1f / w, 1f / h));
                cmd.SetComputeTextureParam(m_Shader, m_Kernel, "_LianCapsuleAOTex", m_Output);
                cmd.SetGlobalTexture(LianFrameData.CapsuleAOTexName, m_Output);
                int gw = Mathf.Max(1, (w / 2) / 8);
                int gh = Mathf.Max(1, (h / 2) / 8);
                cmd.DispatchCompute(m_Shader, m_Kernel, gw, gh, 1);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
