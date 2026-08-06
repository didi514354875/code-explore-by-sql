using System.Runtime.InteropServices;
using UnityEngine;

namespace NPRCloth
{
    /// <summary>
    /// 附加光源风格化参数打包(与 shader 侧 ClothStylizedLightData 1:1,共 8 个 float4)。
    /// 槽位对应原始 cb3[light*64+6..62]:
    ///   colorAndType:         rgb 颜色(含强度) w 类型(0点光 1聚光,>=2 跳过)
    ///   positionAndInvRadius: xyz 位置 w 1/range
    ///   tangentAndCapsule:    x,y 半八面体切线打包 w 胶囊长度(0=非胶囊) z 预留
    ///   modeParams0:          xyz=(cosInner, cosOuter, 1/(cosInner-cosOuter)) w=renderMode(0-4)
    ///   modeParams1:          按模式复用(x/y/z/w)
    ///   tangentWS:            xyz 全精度切线世界方向
    ///   spotDirWS:            xyz 聚光方向 w 非mode4衰减指数
    ///   specularParams:       z=高光强度
    /// </summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct ClothStylizedLightData
    {
        public Vector4 colorAndType;
        public Vector4 positionAndInvRadius;
        public Vector4 tangentAndCapsule;
        public Vector4 modeParams0;
        public Vector4 modeParams1;
        public Vector4 tangentWS;
        public Vector4 spotDirWS;
        public Vector4 specularParams;

        public const int SizeInBytes = 8 * 16;
    }

    /// <summary>
    /// 挂在 Light 上定义 Cloth/Skin/Face shader 附加光的风格化参数。
    /// renderMode 0-4:
    ///   0 普通(无阴影 + ramp 色 + 普通高光);
    ///   1 包裹;
    ///   2 仅高光(粗糙度阈值/替换/金属联动);
    ///   3 背光;
    ///   4 直接 ndotl 混合(仅 Cloth 使用;Skin/Face 使用 0-3 + 胶囊长度字段)。
    /// paramX/Y/Z/W 按模式解释(Inspector 标签随 renderMode 切换)。
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(Light))]
    public class ClothStylizedLight : MonoBehaviour
    {
        [Tooltip("0 普通 / 1 包裹 / 2 仅高光 / 3 背光 / 4 直接混合(仅 Cloth 使用;Skin/Face 使用 0-3 + 胶囊长度字段)")]
        [Range(0, 4)] public int renderMode;

        [Tooltip("胶囊光源长度(0 = 非胶囊;仅点光生效)")]
        public float capsuleLength;

        [Tooltip("切线世界方向(半八面体打包);为零时用 cross(up, forward) 兜底")]
        public Vector3 tangent = new Vector3(1f, 0f, 0f);

        [Tooltip("非 mode4 的衰减指数(URP 衰减替换后仅供记录/扩展)")]
        public float falloffExponent = 2f;

        public float specularStrength = 1f;

        [Header("Mode Params")]
        [Tooltip("mode0: 漫反射包裹下限 | mode1: 包裹偏移 | mode2: 粗糙度阈值 | mode3: 背光范围 | mode4: 强度")]
        public float paramX;
        [Tooltip("mode0: 颜色归一化混合 | mode1: shadowDiif 强度 | mode2: 粗糙度替换混合 | mode3: 背光对比 | mode4: 衰减指数")]
        public float paramY;
        [Tooltip("mode0/1/3: 未使用 | mode2: 金属联动 | mode4: 固定方向阈值(>0.5 用固定方向)")]
        public float paramZ;
        [Tooltip("mode0/1/2/3: 未使用 | mode4: radian 混合")]
        public float paramW;

        [Header("Spot Angles")]
        [Tooltip("聚光内角(度);0 = light.innerSpotAngle(无则等于外角,硬边)")]
        public float innerAngle;
        [Tooltip("聚光外角(度);0 = light.spotAngle")]
        public float outerAngle;

        Light m_Light;

        void Awake() { m_Light = GetComponent<Light>(); }

        /// <summary>打包本帧的光数据(与 shader 侧槽位一一对应)。isSpot 由调用方按 Light.type 判定。</summary>
        public ClothStylizedLightData GetData(Light light, bool isSpot)
        {
            var d = new ClothStylizedLightData();

            // 类型:点光=0, 聚光=1, 其他=2(>=2 时 shader 跳过)
            d.colorAndType = new Vector4(
                light.color.r * light.intensity,
                light.color.g * light.intensity,
                light.color.b * light.intensity,
                isSpot ? 1f : 0f);
            d.positionAndInvRadius = new Vector4(
                light.transform.position.x, light.transform.position.y, light.transform.position.z,
                1f / Mathf.Max(light.range, 0.001f));

            // 切线半八面体打包(与 shader DecodeClothTangent 互逆,由 asm 807-817 解码逆推):
            //   解码 r16 = (b, y, a):a = P/2+0.5-|X|, b = P-a, y = sign(X)*max(0, 1-|a|-|b|)
            //   令 a=k*tz, b=k*tx, y=k*ty -> k = 1/(|tx|+|ty|+|tz|):
            //     X = sign(ty) * (1 + (tx-tz)/L1) / 2, P = (tx+tz) / L1
            //   (计划原公式 X=sign(ty)(1-tx+tz)/2, P=tx+tz 无法通过验证第 8 条,误差最大 176°)
            // 聚光时切线 = -spotDir(保证 shader 的 dot(curLightDir, -tangent) 语义与打包一致)
            Vector3 t = tangent;
            if (t.sqrMagnitude < 1e-6f)
            {
                // 兜底基:cross(up, light.forward),退化时 (1,0,0)
                t = Vector3.Cross(Vector3.up, light.transform.forward);
                if (t.sqrMagnitude < 1e-6f) t = Vector3.right;
            }
            t.Normalize();
            Vector3 packTangent = isSpot ? -light.transform.forward : t;
            float l1 = Mathf.Abs(packTangent.x) + Mathf.Abs(packTangent.y) + Mathf.Abs(packTangent.z);
            float signY = packTangent.y >= 0f ? 1f : -1f;
            float packedX = l1 > 1e-9f ? signY * (1f + (packTangent.x - packTangent.z) / l1) * 0.5f : 0f;
            float packedP = l1 > 1e-9f ? (packTangent.x + packTangent.z) / l1 : 0f;
            d.tangentAndCapsule = new Vector4(packedX, packedP, 0f, capsuleLength);

            // 聚光角度(度 -> cos 半角;cosInner - cosOuter 的倒数进 rcpRange)
            float outer = outerAngle > 0f ? outerAngle : light.spotAngle;
            float inner = innerAngle > 0f ? innerAngle
                : (light.innerSpotAngle > 0f ? light.innerSpotAngle : light.spotAngle);
            float cosOuter = Mathf.Cos(outer * 0.5f * Mathf.Deg2Rad);
            float cosInner = Mathf.Cos(inner * 0.5f * Mathf.Deg2Rad);
            d.modeParams0 = new Vector4(cosInner, cosOuter, 1f / Mathf.Max(cosInner - cosOuter, 1e-6f), renderMode);

            // 模式参数(槽位复用,含义按模式)
            d.modeParams1 = new Vector4(paramX, paramY, paramZ, paramW);

            // 全精度切线(与打包值同源:聚光时 = -spotDir)
            d.tangentWS = new Vector4(packTangent.x, packTangent.y, packTangent.z, 0f);

            // 聚光方向(URP 约定:transform.forward 指向光源照射方向)
            Vector3 spotDir = light.transform.forward;
            d.spotDirWS = new Vector4(spotDir.x, spotDir.y, spotDir.z, falloffExponent);

            d.specularParams = new Vector4(0f, 0f, specularStrength, 0f);
            return d;
        }
    }
}
