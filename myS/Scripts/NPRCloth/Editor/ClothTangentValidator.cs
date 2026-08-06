using UnityEditor;
using UnityEngine;

namespace NPRCloth.EditorTools
{
    /// <summary>
    /// 切线半八面体打包自检:随机 1000 个归一化方向,encode(decode) 后最大夹角误差应 < 0.5°;
    /// 误差 > 1° 视为打包公式错误(回查 asm 807-817 解码与 ClothStylizedLight.GetData)。
    /// 菜单:Tools/NPRCloth/ValidateTangentEncode
    /// </summary>
    public static class ClothTangentValidator
    {
        const int k_SampleCount = 1000;
        const float k_MaxAngleDegrees = 1f;

        /// <summary>C# 侧打包(与 ClothStylizedLight.GetData 同公式,L1 归一化,由 asm 解码逆推)。</summary>
        public static Vector2 Encode(Vector3 t)
        {
            float l1 = Mathf.Abs(t.x) + Mathf.Abs(t.y) + Mathf.Abs(t.z);
            if (l1 < 1e-9f)
                return Vector2.zero;
            float signY = t.y >= 0f ? 1f : -1f;
            float x = signY * (1f + (t.x - t.z) / l1) * 0.5f;
            float p = (t.x + t.z) / l1;
            return new Vector2(x, p);
        }

        /// <summary>shader 侧解码(与 ClothLighting.hlsl DecodeClothTangent 同公式)。</summary>
        public static Vector3 Decode(Vector2 packed)
        {
            float pp = packed.y * 0.5f + 0.5f;
            float a = pp - Mathf.Abs(packed.x);
            float b = packed.y - a;
            float y = packed.x >= 0f ? Mathf.Max(1f - Mathf.Abs(a) - Mathf.Abs(b), 0f)
                                     : -Mathf.Max(1f - Mathf.Abs(a) - Mathf.Abs(b), 0f);
            return new Vector3(b, y, a).normalized;
        }

        [MenuItem("Tools/NPRCloth/ValidateTangentEncode")]
        public static void Validate()
        {
            float maxAngle = 0f;
            Vector3 worst = Vector3.zero;
            var rng = new System.Random(12345);
            for (int i = 0; i < k_SampleCount; ++i)
            {
                Vector3 t = new Vector3(
                    (float)rng.NextDouble() * 2f - 1f,
                    (float)rng.NextDouble() * 2f - 1f,
                    (float)rng.NextDouble() * 2f - 1f).normalized;
                Vector3 decoded = Decode(Encode(t));
                float angle = Vector3.Angle(t, decoded);
                if (angle > maxAngle)
                {
                    maxAngle = angle;
                    worst = t;
                }
            }
            Debug.Log($"[NPRCloth] TangentEncode: {k_SampleCount} samples, max angle error = {maxAngle:F4}° (worst dir {worst}). Threshold: 0.5° target, >{k_MaxAngleDegrees}° = formula error.");
            if (maxAngle > k_MaxAngleDegrees)
                Debug.LogError("[NPRCloth] TangentEncode FAILED: 打包/解码公式不一致,请回查 asm 807-817 与 ClothStylizedLight.GetData。");
            else if (maxAngle > 0.5f)
                Debug.LogWarning("[NPRCloth] TangentEncode: 误差在 0.5°-1° 之间(越界方向近似,可接受)。");
        }
    }
}
