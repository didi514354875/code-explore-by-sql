using UnityEngine;

namespace LianYunShenKong
{
    /// <summary>
    /// 胶囊遮挡体组件,与 dump `_20._m5[64]` 两槽一组对应:
    /// 偶槽 2i = (center.xyz, radius.w),奇槽 2i+1 = (dir.xyz, length.w)。
    /// </summary>
    [DisallowMultipleComponent]
    public class LianCapsuleAO : MonoBehaviour
    {
        [Tooltip("胶囊轴长(沿本地 -Z 方向)")]
        public float length = 2.0f;

        [Tooltip("胶囊半径")]
        public float radius = 0.25f;

        public CapsuleShape GetShape()
        {
            Vector3 center = transform.position;
            // 胶囊轴向:本地 -Z(dump 以锥体方向为轴,伸向场景)
            Vector3 dir = -transform.forward;
            dir.Normalize();

            var shape = new CapsuleShape();
            shape.centerRadius = new Vector4(center.x, center.y, center.z, Mathf.Max(radius, 0.001f));
            shape.dirLength = new Vector4(dir.x, dir.y, dir.z, Mathf.Max(length, 0.01f));
            return shape;
        }
    }
}
