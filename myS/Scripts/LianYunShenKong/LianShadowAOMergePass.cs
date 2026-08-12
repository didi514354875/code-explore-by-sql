using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// pass 11/12/13/15:shadow+AO 合并到 _LianShadowAOTex(r=级联, g=soft, b=空, a=AO)。
    /// 11 非过渡区(stencil Ref 1 Replace)→ 12 过渡区(stencil NotEqual,精确 PCF)→
    /// 13 soft(g,ColorMask G,16 tap)→ 15 capsule min(a)。见 LianShadowAOMerge.shader。
    /// </summary>
    public class LianShadowAOMergePass : ScriptableRenderPass
    {
        RTHandle m_Output;
        Material m_Material;

        public RTHandle output => m_Output;

        /// <summary>pass 8 的 _LianHalfResDepth(深度 + stencil 必须复用同一 RT)</summary>
        public RTHandle halfDepthRT;
        public float capsuleNormDist = 200f;
        public float transitionShadowMax = 0.9f;

        public LianShadowAOMergePass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianShadowAOMergePass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/ShadowAOMerge");
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
            desc.graphicsFormat = GraphicsFormat.R8G8B8A8_UNorm;
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Point, TextureWrapMode.Clamp, name: LianFrameData.ShadowAOTexName);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null || halfDepthRT == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth);
            int h = Mathf.Max(1, cameraData.camera.pixelHeight);

            CommandBuffer cmd = CommandBufferPool.Get("LianShadowAOMerge");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalVector("_LianScreenSize", new Vector4(w, h, 0f, 0f));
                cmd.SetGlobalVector("_LianMergeParams", new Vector4(transitionShadowMax, 0f, 0f, 0f));
                cmd.SetGlobalFloat("_LianCapsuleAONormDist", capsuleNormDist);

                cmd.SetGlobalTexture(LianFrameData.ShadowAOTexName, m_Output);
                if (m_SharedDepthRT != null && m_SharedDepthRT.rt != null)
                    cmd.SetGlobalTexture("_CameraDepthTexture", m_SharedDepthRT);

                // 目标 = 输出颜色 + 半分辨率深度/模板;仅清颜色,保留 pass 8 的深度与模板
                cmd.SetRenderTarget(m_Output.nameID, halfDepthRT.nameID);
                cmd.ClearRenderTarget(false, true, Color.clear);

                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3);   // 11
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 1, MeshTopology.Triangles, 3);   // 12
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 2, MeshTopology.Triangles, 3);   // 13
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 3, MeshTopology.Triangles, 3);   // 15
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
