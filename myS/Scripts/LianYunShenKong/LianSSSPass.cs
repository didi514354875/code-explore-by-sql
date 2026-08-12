using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// pass 19:可分离 SSS 横/纵模糊,采样 _LianLinearDepthTex + _LianSkinDiffuseTex + _LianSkinProfileTex,
    /// 输出 _LianSSSTex。见 LianSSSBlur.shader(dump `_64`)。
    /// </summary>
    public class LianSSSPass : ScriptableRenderPass
    {
        RTHandle m_Output;
        RTHandle m_TempRT;
        Material m_Material;

        public RTHandle output => m_Output;

        public float sssScale = 2.0f;
        public int steps = 5;
        public Vector4[] kernel = new Vector4[]
        {
            new Vector4(0.227027f, 0f, 0f, 0f),
            new Vector4(0.194595f, 0f, 0f, 1f),
            new Vector4(0.121622f, 0f, 0f, 2f),
            new Vector4(0.054054f, 0f, 0f, 3f),
            new Vector4(0.016216f, 0f, 0f, 4f),
        };

        public LianSSSPass()
        {
            profilingSampler = new ProfilingSampler(nameof(LianSSSPass));
            m_Material = CreateMaterial("Hidden/LianYunShenKong/SSSBlur");
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
            RenderingUtils.ReAllocateIfNeeded(ref m_Output, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: LianFrameData.SSSTexName);
            RenderingUtils.ReAllocateIfNeeded(ref m_TempRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_LianSSSTemp");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null || m_Output == null || m_TempRT == null)
                return;

            var cameraData = renderingData.cameraData;
            int w = Mathf.Max(1, cameraData.camera.pixelWidth / 2);
            int h = Mathf.Max(1, cameraData.camera.pixelHeight / 2);

            CommandBuffer cmd = CommandBufferPool.Get("LianSSSPass");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.SetGlobalVector("_LianSSSTexelSize", new Vector2(1f / w, 1f / h));
                cmd.SetGlobalFloat("_LianSSSScale", sssScale);
                cmd.SetGlobalInt("_LianSSSSteps", steps);
                cmd.SetGlobalVectorArray("_LianSSSKernel", kernel);

                // 横向 → 临时 RT
                cmd.SetGlobalFloat("_LianSSSDirection", 0f);
                CoreUtils.SetRenderTarget(cmd, m_TempRT, ClearFlag.Color, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 0, MeshTopology.Triangles, 3);

                // 纵向 ← 临时 RT → 输出
                cmd.SetGlobalTexture(LianFrameData.SkinDiffuseTexName, m_TempRT);
                cmd.SetGlobalFloat("_LianSSSDirection", 1f);
                cmd.SetGlobalTexture(LianFrameData.SSSTexName, m_Output);
                CoreUtils.SetRenderTarget(cmd, m_Output, ClearFlag.Color, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, m_Material, 1, MeshTopology.Triangles, 3);

                // 恢复皮肤 diffuse 全局绑定(下一帧 pass 16 会重新绑定)
                cmd.SetGlobalTexture(LianFrameData.SkinDiffuseTexName, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
