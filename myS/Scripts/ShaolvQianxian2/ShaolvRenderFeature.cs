using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ShaolvQianxian2
{
    /// <summary>
    /// 少女前线2 角色 shader(ShaolvQianxian2.shader)渲染注入:
    /// 1) 以 3 个 MRT(颜色 / 法线遮罩 / 屏幕空间偏移)渲染 LightMode = ShaolvForward 的物体
    ///    —— 对应原始 PS 的 o0/o1/o2 三个输出;
    /// 2) 每帧打包附加光数据到 StructuredBuffer(原 cb0[li+10]/[li+266]/[li+522]/[li+778]);
    /// 3) 每帧设置帧级全局(级联偏移 cb0[2721..2722]、环境光方向 cb0[1337..1341]、
    ///    屏幕抖动 cb0[2782]、窗户遮罩 cb0[2757])。
    /// 主光方向/颜色、级联阴影矩阵/球/尺寸、SH 系数、反射探针均直接使用 URP 内置全局。
    /// </summary>
    [DisallowMultipleComponent]
    public class ShaolvRenderFeature : ScriptableRendererFeature
    {
        static readonly int k_LightsBufferId = Shader.PropertyToID("_ShaolvAdditionalLights");
        static readonly int k_EnvLightDirMatrixId = Shader.PropertyToID("_EnvLightDirMatrix");
        static readonly int k_EnvLightRefDirId = Shader.PropertyToID("_EnvLightRefDir");
        static readonly int k_CascadeDepthBiasId = Shader.PropertyToID("_CascadeDepthBias");
        static readonly int k_CascadeNormalBiasId = Shader.PropertyToID("_CascadeNormalBias");
        static readonly int k_ScreenSpaceDitherId = Shader.PropertyToID("_ScreenSpaceDither");
        static readonly int k_WindowMaskStrengthId = Shader.PropertyToID("_WindowMaskStrength");

        [Header("MRT 渲染")]
        [Tooltip("渲染不透明队列(RenderType/Queue = Opaque)")]
        public bool renderOpaque = true;
        [Tooltip("渲染透明队列(需材质 RenderType/Queue 改为 Transparent)")]
        public bool renderTransparent = false;

        [Header("环境光参数(原 cb0[1337..1341])")]
        [Tooltip("环境光方向矩阵第一列,决定卡通环境 ramp 的 ldotenvL 符号;零向量时用主光方向")]
        public Vector3 envLightDir = Vector3.zero;
        [Tooltip("环境光参考方向(原 cb0[1341]);零向量时用主光方向")]
        public Vector3 envLightRefDir = Vector3.zero;

        [Header("帧级参数")]
        [Tooltip("屏幕空间抖动偏移(原 cb0[2782].xy,叠加到 o2.xy)")]
        public Vector2 screenSpaceDither = Vector2.zero;
        [Tooltip("窗户效果强度(原 cb0[2757].x,o1.w = 0.5 - x*0.5)")]
        public float windowMaskStrength = 0f;

        /// <summary>法线遮罩 RT(验证用,原 PS o1)。</summary>
        public RenderTexture normalMaskRT => m_NormalMaskRT;
        /// <summary>屏幕空间偏移 RT(验证用,原 PS o2)。</summary>
        public RenderTexture screenOffsetRT => m_ScreenOffsetRT;

        ShaolvForwardPass m_OpaquePass;
        ShaolvForwardPass m_TransparentPass;
        ShaderTagId m_ShaolvForwardTag;
        ComputeBuffer m_LightsBuffer;
        ShaolvAdditionalLightData[] m_LightDataArray;
        RenderTexture m_NormalMaskRT;
        RenderTexture m_ScreenOffsetRT;

        /// <summary>一个附加光的着色数据,与原始 cb0 每光槽位一一对应。</summary>
        struct ShaolvAdditionalLightData
        {
            public Vector4 positionAndType;   // cb0[li+10]: xyz 光源位置, w = 0 方向光/1 位置光
            public Vector4 color;             // cb0[li+266]: rgb 颜色(含强度)
            public Vector4 rangeSpot;         // cb0[li+522]: x = 1/range², z = 聚光衰减 scale, w = 聚光衰减 bias
            public Vector4 spotDir;           // cb0[li+778]: xyz 聚光方向(世界)
        }

        public override void Create()
        {
            m_ShaolvForwardTag = new ShaderTagId("ShaolvForward");
            m_OpaquePass = new ShaolvForwardPass
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques,
                renderQueueRange = RenderQueueRange.opaque,
                sortCriteria = SortingCriteria.CommonOpaque,
            };
            m_TransparentPass = new ShaolvForwardPass
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingTransparents,
                renderQueueRange = RenderQueueRange.transparent,
                sortCriteria = SortingCriteria.CommonTransparent,
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.cameraType == CameraType.Preview)
                return;

            Camera camera = renderingData.cameraData.camera;
            int w = camera.pixelWidth;
            int h = camera.pixelHeight;
            if (m_NormalMaskRT == null || m_NormalMaskRT.width != w || m_NormalMaskRT.height != h)
            {
                if (m_NormalMaskRT != null) m_NormalMaskRT.Release();
                if (m_ScreenOffsetRT != null) m_ScreenOffsetRT.Release();
                m_NormalMaskRT = new RenderTexture(w, h, 0, RenderTextureFormat.ARGB32);
                m_ScreenOffsetRT = new RenderTexture(w, h, 0, RenderTextureFormat.ARGB32);
                m_NormalMaskRT.name = "_ShaolvNormalMaskRT";
                m_ScreenOffsetRT.name = "_ShaolvScreenOffsetRT";
            }

            // 仅分配 MRT(颜色/深度目标在 OnCameraSetup 阶段经 ConfigureTarget 绑定)
            m_OpaquePass.normalMaskRT = m_NormalMaskRT;
            m_OpaquePass.screenOffsetRT = m_ScreenOffsetRT;
            m_OpaquePass.shaderTagId = m_ShaolvForwardTag;
            m_TransparentPass.normalMaskRT = m_NormalMaskRT;
            m_TransparentPass.screenOffsetRT = m_ScreenOffsetRT;
            m_TransparentPass.shaderTagId = m_ShaolvForwardTag;

            if (renderOpaque)
                renderer.EnqueuePass(m_OpaquePass);
            if (renderTransparent)
                renderer.EnqueuePass(m_TransparentPass);
        }

        protected override void Dispose(bool disposing)
        {
            m_LightsBuffer?.Release();
            m_LightsBuffer = null;
            if (m_NormalMaskRT != null)
            {
                m_NormalMaskRT.Release();
                m_NormalMaskRT = null;
            }
            if (m_ScreenOffsetRT != null)
            {
                m_ScreenOffsetRT.Release();
                m_ScreenOffsetRT = null;
            }
        }

        class ShaolvForwardPass : ScriptableRenderPass
        {
            public ShaderTagId shaderTagId;
            public RenderTexture normalMaskRT;
            public RenderTexture screenOffsetRT;
            public RenderQueueRange renderQueueRange;
            public SortingCriteria sortCriteria;
            public ComputeBuffer lightsBuffer;
            public ShaolvAdditionalLightData[] lightDataArray;
            public Vector3 envLightDir;
            public Vector3 envLightRefDir;
            public Vector2 screenSpaceDither;
            public float windowMaskStrength;

            // 颜色目标用渲染器主颜色附件,深度用渲染器深度附件(经 ConfigureTarget 由 URP 绑定)
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTargetIdentifier[] targets =
                {
                    renderingData.cameraData.renderer.cameraColorTargetHandle,
                    normalMaskRT,
                    screenOffsetRT,
                };
                ConfigureTarget(targets, renderingData.cameraData.renderer.cameraDepthTargetHandle);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get("ShaolvForward");

                // ---- 附加光打包(原 cb0[li+10]/[li+266]/[li+522]/[li+778];索引跳过主光,与 URP 附加光索引一致) ----
                NativeArray<VisibleLight> visibleLights = renderingData.lightData.visibleLights;
                int mainLightIndex = renderingData.lightData.mainLightIndex;
                int additionalCount = renderingData.lightData.additionalLightsCount;
                if (lightsBuffer == null || lightsBuffer.count < Mathf.Max(additionalCount, 1))
                {
                    lightsBuffer?.Release();
                    lightsBuffer = new ComputeBuffer(Mathf.Max(additionalCount, 1),
                        System.Runtime.InteropServices.Marshal.SizeOf<ShaolvAdditionalLightData>());
                }
                if (additionalCount > 0)
                {
                    if (lightDataArray == null || lightDataArray.Length < additionalCount)
                        lightDataArray = new ShaolvAdditionalLightData[additionalCount];
                    for (int i = 0; i < additionalCount; i++)
                    {
                        int vlIndex = (mainLightIndex < 0) ? i : (i < mainLightIndex ? i : i + 1);
                        VisibleLight vl = visibleLights[vlIndex];
                        Light light = vl.light;
                        bool isDir = vl.lightType == LightType.Directional;

                        // 光指向方向(指向光源;URP DirectionalLightDirection 同款)
                        Vector3 forward = vl.localToWorldMatrix.GetColumn(2);
                        Vector3 position = vl.localToWorldMatrix.GetColumn(3);

                        ShaolvAdditionalLightData d;
                        d.positionAndType = isDir
                            ? new Vector4(-forward.x, -forward.y, -forward.z, 0f)
                            : new Vector4(position.x, position.y, position.z, 1f);

                        float invRangeSqr = isDir ? 0f : 1f / (light.range * light.range);
                        float spotScale = 0f;
                        float spotBias = 0f;
                        if (vl.lightType == LightType.Spot)
                        {
                            float cosOuter = Mathf.Cos(light.spotAngle * 0.5f * Mathf.Deg2Rad);
                            float cosInner = Mathf.Cos(light.innerSpotAngle * 0.5f * Mathf.Deg2Rad);
                            spotScale = 1f / Mathf.Max(cosInner - cosOuter, 1e-4f);
                            spotBias = -cosOuter * spotScale;
                        }
                        d.rangeSpot = new Vector4(invRangeSqr, 0f, spotScale, spotBias);
                        d.spotDir = new Vector4(forward.x, forward.y, forward.z, 0f);
                        d.color = new Vector4(light.color.r * light.intensity,
                                              light.color.g * light.intensity,
                                              light.color.b * light.intensity, 1f);
                        lightDataArray[i] = d;
                    }
                    lightsBuffer.SetData(lightDataArray, 0, 0, additionalCount);
                    cmd.SetGlobalBuffer(k_LightsBufferId, lightsBuffer);
                }
                else
                {
                    cmd.SetGlobalBuffer(k_LightsBufferId, lightsBuffer);
                }

                // ---- 帧级全局 ----
                Vector3 mainLightDir = Vector3.forward;
                float depthBias = 0f;
                float normalBias = 0f;
                if (mainLightIndex >= 0)
                {
                    Light mainLight = visibleLights[mainLightIndex].light;
                    mainLightDir = -mainLight.transform.forward;   // 指向光源
                    depthBias = mainLight.shadowBias;
                    normalBias = mainLight.shadowNormalBias;
                }
                // 级联偏移(原 cb0[2721..2722],4 级联同值)
                cmd.SetGlobalVector(k_CascadeDepthBiasId, new Vector4(depthBias, depthBias, depthBias, depthBias));
                cmd.SetGlobalVector(k_CascadeNormalBiasId, new Vector4(normalBias, normalBias, normalBias, normalBias));

                // 环境光方向(原 cb0[1337..1341];零向量回退主光方向)
                Vector3 eDir = envLightDir.sqrMagnitude > 0.0001f ? envLightDir.normalized : mainLightDir;
                Vector3 refDir = envLightRefDir.sqrMagnitude > 0.0001f ? envLightRefDir.normalized : mainLightDir;
                Vector3 t = Vector3.Cross(eDir, Vector3.up);
                if (t.sqrMagnitude < 1e-6f)
                    t = Vector3.Cross(eDir, Vector3.right);
                t.Normalize();
                Vector3 b = Vector3.Cross(t, eDir);
                Matrix4x4 envMatrix = Matrix4x4.identity;
                envMatrix.SetColumn(0, eDir);
                envMatrix.SetColumn(1, t);
                envMatrix.SetColumn(2, b);
                cmd.SetGlobalMatrix(k_EnvLightDirMatrixId, envMatrix);
                cmd.SetGlobalVector(k_EnvLightRefDirId, new Vector4(refDir.x, refDir.y, refDir.z, 0f));

                cmd.SetGlobalVector(k_ScreenSpaceDitherId, new Vector4(screenSpaceDither.x, screenSpaceDither.y, 0f, 0f));
                cmd.SetGlobalFloat(k_WindowMaskStrengthId, windowMaskStrength);

                // ---- 渲染 ShaolvForward 物体(颜色/深度已由 ConfigureTarget 绑定) ----
                // cmd.ClearRenderTarget(false, true, Color.clear);   // 调试:验证 MRT 绑定

                DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagId, ref renderingData, sortCriteria);
                FilteringSettings filteringSettings = new FilteringSettings(renderQueueRange);
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
    }
}
