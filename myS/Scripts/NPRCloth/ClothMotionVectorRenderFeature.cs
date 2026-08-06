using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace NPRCloth
{
    /// <summary>
    /// 运动矢量渲染(可选,默认禁用):motionVectorRT 非空时在 AfterRenderingTransparents 注入,
    /// 用 Cloth.shader 的 LightMode = ClothMotionVectors pass(_MOTION_VECTOR_PASS 关键字)把
    /// EncodeClothMotionVector 结果画进 RT。蒙皮物体上一帧位置 Unity 不提供,输出 ≈0 速度(可接受)。
    /// </summary>
    [DisallowMultipleComponent]
    public class ClothMotionVectorRenderFeature : ScriptableRendererFeature
    {
        [Tooltip("目标 RT;为空时该 pass 不注入")]
        public RenderTexture motionVectorRT;

        [Tooltip("每帧清除 RT")]
        public bool clearRT = true;

        MotionVectorPass m_Pass;
        Material m_OverrideMaterial;

        static readonly ShaderTagId k_MotionVectorTag = new ShaderTagId("ClothMotionVectors");

        public override void Create()
        {
            m_Pass = new MotionVectorPass();
            m_Pass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (motionVectorRT == null)
                return;
            if (renderingData.cameraData.cameraType == CameraType.Preview)
                return;
            EnsureOverrideMaterial();
            if (m_OverrideMaterial == null)
                return;
            m_Pass.target = motionVectorRT;
            m_Pass.clearRT = clearRT;
            m_Pass.overrideMaterial = m_OverrideMaterial;
            renderer.EnqueuePass(m_Pass);
        }

        void EnsureOverrideMaterial()
        {
            if (m_OverrideMaterial == null)
            {
                var shader = Shader.Find(ClothMaterialSetup.ShaderName);
                if (shader == null)
                    return;
                m_OverrideMaterial = new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
                m_OverrideMaterial.EnableKeyword("_MOTION_VECTOR_PASS");
            }
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass = null;
            if (m_OverrideMaterial != null)
            {
                if (Application.isPlaying)
                    Destroy(m_OverrideMaterial);
                else
                    DestroyImmediate(m_OverrideMaterial);
                m_OverrideMaterial = null;
            }
        }

        class MotionVectorPass : ScriptableRenderPass
        {
            public RenderTexture target;
            public bool clearRT;
            public Material overrideMaterial;

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (target == null || overrideMaterial == null)
                    return;
                CommandBuffer cmd = CommandBufferPool.Get("ClothMotionVectors");
                cmd.SetRenderTarget(target);
                if (clearRT)
                    cmd.ClearRenderTarget(true, true, Color.clear);

                // 只画挂 Cloth/Skin/Face shader 材质的渲染器(调试用途,逐渲染器提交;统一用 Cloth 材质 override 出运动矢量)
                var renderers = Object.FindObjectsOfType<Renderer>();
                foreach (var r in renderers)
                {
                    if (r == null) continue;
                    bool hasCloth = false;
                    foreach (var mat in r.sharedMaterials)
                    {
                        if (mat != null && ClothMaterialSetup.IsCharacterShader(mat.shader))
                        {
                            hasCloth = true;
                            break;
                        }
                    }
                    if (!hasCloth) continue;

                    var meshFilter = r.GetComponent<MeshFilter>();
                    if (meshFilter != null && meshFilter.sharedMesh != null)
                    {
                        cmd.DrawMesh(meshFilter.sharedMesh, r.localToWorldMatrix, overrideMaterial, 0, 0);
                    }
                    else
                    {
                        var skinned = r as SkinnedMeshRenderer;
                        if (skinned != null && skinned.sharedMesh != null)
                        {
                            var baked = new Mesh();
                            skinned.BakeMesh(baked);
                            // BakeMesh 输出世界空间网格
                            cmd.DrawMesh(baked, Matrix4x4.identity, overrideMaterial, 0, 0);
                            DestroyImmediate(baked);
                        }
                    }
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
    }
}
