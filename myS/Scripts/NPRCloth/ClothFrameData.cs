using UnityEngine;

namespace NPRCloth
{
    /// <summary>
    /// 挂在相机上:每帧设置 Cloth shader 的帧级全局常量。
    /// _NonJitteredVP / _PrevViewProjMatrix 对应原始 cb0[24..27] / cb0[37..40](运动矢量);
    /// _MipBias 对应 cb0[88].x(全局 mip bias,整数位供雾 LUT hash 使用)。
    /// </summary>
    [RequireComponent(typeof(Camera))]
    [DisallowMultipleComponent]
    public class ClothFrameData : MonoBehaviour
    {
        [Tooltip("全局 mip bias,透传给 cb0[88].x")]
        public float mipBias = 0f;

        Camera m_Camera;
        Matrix4x4 m_PrevViewProj;

        void Awake()
        {
            m_Camera = GetComponent<Camera>();
            // 材质回退兜底(白纹理等)
            ClothMaterialSetup.EnsureFallbacks();
        }

        void OnEnable()
        {
            m_Camera = GetComponent<Camera>();
            // 首帧:上一帧矩阵 = 当前矩阵(运动矢量 ≈ 0)
            m_PrevViewProj = m_Camera.nonJitteredProjectionMatrix * m_Camera.worldToCameraMatrix;
        }

        void Update()
        {
            Matrix4x4 viewProj = m_Camera.nonJitteredProjectionMatrix * m_Camera.worldToCameraMatrix;
            Shader.SetGlobalMatrix("_NonJitteredVP", viewProj);
            Shader.SetGlobalMatrix("_PrevViewProjMatrix", m_PrevViewProj);
            Shader.SetGlobalFloat("_MipBias", mipBias);
            // 雾默认关(对应原始 cb0[171].w = 1);挂 ClothFogVolume 时置 0(Skin/Face 的 _FogEnabled 门)
            Shader.SetGlobalFloat("_FogEnabled", 1f);
            m_PrevViewProj = viewProj;
        }
    }
}
