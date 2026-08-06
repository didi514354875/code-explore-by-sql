using System;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace NPRCloth
{
    /// <summary>
    /// 附加光源风格化参数注入:遍历可见点光/聚光(挂 ClothStylizedLight),按
    /// cullingResults.GetLightIndexMap()(visibleLightIndex -> _AdditionalLights* UBO 槽位)写入
    /// _StylizedLightParamsBuffer(StructuredBuffer),并在渲染前绑定全局。
    /// 未挂组件的点光不产生任何贡献(槽位保持 0 -> renderMode 0 且颜色 0)。
    /// </summary>
    public class StylizedLightRenderFeature : ScriptableRendererFeature
    {
        [Tooltip("缓冲尺寸;0 = UniversalRenderPipeline.maxVisibleAdditionalLights(与 shader MAX_VISIBLE_LIGHTS 一致)")]
        public int bufferSize = 0;

        StylizedLightPass m_Pass;

        public override void Create()
        {
            m_Pass = new StylizedLightPass();
            m_Pass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.cameraType == CameraType.Preview)
                return;
            renderer.EnqueuePass(m_Pass);
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass?.DisposeBuffer();
        }

        class StylizedLightPass : ScriptableRenderPass
        {
            const string k_ShaderBufferName = "_StylizedLightParamsBuffer";

            ComputeBuffer m_Buffer;
            ClothStylizedLightData[] m_Data;
            int m_AllocatedSize;

            public void DisposeBuffer()
            {
                if (m_Buffer != null)
                {
                    m_Buffer.Release();
                    m_Buffer = null;
                }
                m_Data = null;
                m_AllocatedSize = 0;
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                int maxLights = UniversalRenderPipeline.maxVisibleAdditionalLights;
                if (maxLights <= 0)
                    return;

                // 缓冲尺寸:与 URP MAX_VISIBLE_LIGHTS 对齐;用户指定更小时截断并告警
                int size = maxLights;
                if (m_AllocatedSize != size || m_Buffer == null)
                {
                    DisposeBuffer();
                    m_Buffer = new ComputeBuffer(size, ClothStylizedLightData.SizeInBytes, ComputeBufferType.Default);
                    m_Data = new ClothStylizedLightData[size];
                    m_AllocatedSize = size;
                }
                Array.Clear(m_Data, 0, m_Data.Length);

                var cullResults = renderingData.cullResults;
                var lightIndexMap = cullResults.GetLightIndexMap(Allocator.Temp);
                var visibleLights = cullResults.visibleLights;
                for (int i = 0; i < visibleLights.Length; ++i)
                {
                    // 只处理点光/聚光且挂 ClothStylizedLight 的光(主光方向光天然被排除)
                    LightType type = visibleLights[i].lightType;
                    if (type != LightType.Point && type != LightType.Spot)
                        continue;
                    Light light = visibleLights[i].light;
                    if (light == null)
                        continue;
                    var component = light.GetComponent<ClothStylizedLight>();
                    if (component == null)
                        continue;

                    int slot = lightIndexMap[i];
                    if (slot < 0 || slot >= m_Data.Length)
                        continue;   // 超出每物体光上限或主光槽位(-1)

                    bool isSpot = type == LightType.Spot;
                    m_Data[slot] = component.GetData(light, isSpot);
                }
                lightIndexMap.Dispose();

                m_Buffer.SetData(m_Data);
                Shader.SetGlobalBuffer(k_ShaderBufferName, m_Buffer);
            }
        }
    }
}
