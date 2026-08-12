using UnityEngine;

namespace LianYunShenKong
{
    /// <summary>
    /// 附加光参数组件,与 dump `_9` 六个数组一一对应。
    /// 位置/方向/颜色优先取自挂载的 Unity Light 组件;曲线参数可在此覆盖。
    /// </summary>
    [RequireComponent(typeof(Light))]
    [DisallowMultipleComponent]
    public class LianLight : MonoBehaviour
    {
        [Header("距离衰减曲线 (_9._m4: atten = saturate(lenSq·y + z) / (lenSq·x + 1))")]
        [Tooltip("曲线弯曲 x:0 = 无分母衰减;越大衰减越快")]
        public float curveBend = 0.0f;
        [Tooltip("y 系数;0 = 自动 -1/range²(距离 range 处衰减为 0)")]
        public float falloffPower = 0.0f;
        [Tooltip("z 截距(默认 1)")]
        public float falloffBias = 1.0f;

        [Header("角度衰减 (_9._m1: atten = saturate(SdotL·x + y)²)")]
        [Tooltip("聚光锥 scale x;0 = 自动从 spotAngle 计算")]
        public float spotScale = 0.0f;
        [Tooltip("聚光锥 bias y;0 = 自动从 spotAngle 计算")]
        public float spotBias = 0.0f;

        [Header("阴影选择 (_9._m6: dot(ShadowAO texel, w))")]
        [Tooltip("权重:x=级联阴影(r), y=soft shadow(g), z=空, w=AO(a)")]
        public Vector4 shadowWeights = new Vector4(1f, 0f, 0f, 1f);

        [Header("颜色")]
        [Tooltip("颜色覆盖;未启用时用 Light.color × intensity")]
        public Color colorOverride = Color.white;
        public bool useColorOverride = false;

        /// <summary>
        /// 打包为 dump `_9` 六数组对应的 LianLightData。
        /// </summary>
        public LianLightData GetData(Light light)
        {
            bool isDirectional = light != null && light.type == LightType.Directional;
            float range = light != null ? Mathf.Max(light.range, 0.01f) : 10f;

            Vector3 pos = transform.position;
            Vector3 forward = transform.forward;

            var data = new LianLightData();
            // dump:w=0 方向光时 `_9._m0.xyz` 存方向(lightDir = pos.xyz);w=1 位置光存位置
            data.posType = isDirectional
                ? new Vector4(-forward.x, -forward.y, -forward.z, 0f)
                : new Vector4(pos.x, pos.y, pos.z, 1f);
            data.spotDir = new Vector4(forward.x, forward.y, forward.z, 0f);

            // 聚光锥:自动从 spotAngle/innerSpotAngle 计算 scale/bias
            bool isSpot = light != null && light.type == LightType.Spot;
            if (isSpot && spotScale == 0f && spotBias == 0f)
            {
                float cosOuter = Mathf.Cos(light.spotAngle * 0.5f * Mathf.Deg2Rad);
                float innerAngle = light.innerSpotAngle > 0f ? light.innerSpotAngle : light.spotAngle;
                float cosInner = Mathf.Cos(innerAngle * 0.5f * Mathf.Deg2Rad);
                float inv = 1f / Mathf.Max(cosInner - cosOuter, 1e-5f);
                data.spotAtten = new Vector4(inv, -cosOuter * inv, 0f, 0f);
            }
            else
            {
                data.spotAtten = new Vector4(spotScale, spotBias, 0f, 0f);
            }

            Color c = useColorOverride ? colorOverride : (light != null ? light.color * light.intensity : Color.white);
            data.color = new Vector4(c.r, c.g, c.b, 1f);

            float y = falloffPower != 0f ? falloffPower : -1f / (range * range);
            data.distAtten = new Vector4(curveBend, y, falloffBias, 0f);

            data.shadowSel = shadowWeights;
            return data;
        }
    }
}
