using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace LianYunShenKong
{
    /// <summary>
    /// 调试视图:AfterRenderingPostProcessing 把选中 RT 原样显示到屏幕。
    /// debugViewRT &gt; 0 时启用;索引对应 feature 的 debugSources 数组(1 = _LianNormalTex ...)。
    /// </summary>
    public class LianDebugView : ScriptableRenderPass
    {
        /// <summary>
        /// 调试用静态覆盖:编辑模式渲染器会重建 feature 实例(序列化字段改动不生效),
        /// 验证工具通过此静态量选择调试 RT(0 = 不覆盖)。
        /// </summary>
        public static int overrideRT;

        public int debugViewRT;      // 0 = 关闭;1..N = 显示第 N 个调试 RT
        public RTHandle[] sources;   // 由 feature 每帧填充(与 debugViewRT 索引一一对应)
        public RTHandle cameraTarget;

        Material m_BlitMaterial;

        public LianDebugView() : base()
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            m_BlitMaterial = CreateBlitMaterial();
        }

        public static Material CreateBlitMaterial()
        {
            Shader shader = Shader.Find("Hidden/Universal Render Pipeline/Blit");
            if (shader == null)
                return null;
            return new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (debugViewRT <= 0 || sources == null || m_BlitMaterial == null)
            {
                return;
            }
            int index = debugViewRT - 1;
            if (index < 0 || index >= sources.Length)
                return;
            RTHandle src = sources[index];
            if (src == null || src.rt == null)
                return;
            RTHandle dst = cameraTarget != null && cameraTarget.rt != null
                ? cameraTarget
                : renderingData.cameraData.renderer.cameraColorTargetHandle;
            if (dst == null || dst.rt == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("LianDebugView");
            Blitter.BlitCameraTexture(cmd, src, dst, m_BlitMaterial, 0);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
