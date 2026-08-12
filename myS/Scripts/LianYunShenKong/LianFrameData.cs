using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace LianYunShenKong
{
    /// <summary>
    /// 帧级共享数据:RT 名注册表(跨文件契约)、灯光/胶囊体数据结构、级联阴影矩阵计算。
    /// dump 对应:着色灯光 `_9._m0[20].._m6[20]`、tile 剔除 `_8._m0[50]`、胶囊体 `_20._m5[64]`、
    /// 级联数据 `_34._m0[20]/_m3[16]/_m4.._m6/_m8/_m9/_m17`。
    /// </summary>
    public static class LianFrameData
    {
        // ---------------- 容量(与 dump 数组长度一致) ----------------
        public const int MaxTileLights = 50;      // _8._m0[50]  tile 剔除
        public const int MaxShadingLights = 20;   // _9._m0.._m6[20]  着色
        public const int MaxCapsuleGroups = 32;   // 32 组 × 2 槽
        public const int CapsuleSlotCount = 64;   // _20._m5[64]
        public const int ShadowMapSize = 2048;    // _34._m17.zw
        public const int ShadowAtlasSlices = 4;   // 3 级联 + 1 特殊光

        // ---------------- RT 名注册表(跨文件契约,不得改名) ----------------
        public const string FogNoiseTexName = "_LianFogNoiseTex";
        public const string TileLightIndexTexName = "_LianTileLightIndexTex";
        public const string ShadowAtlasTexName = "_LianShadowAtlasTex";
        public const string NormalTexName = "_LianNormalTex";
        public const string MotionVectorTexName = "_LianMotionVectorTex";
        public const string CascadeShadowTexName = "_LianCascadeShadowTex";
        public const string CameraDepthCopyName = "_LianCameraDepthCopy";
        public const string ChainDepthName = "_LianChainDepth";
        public const string LinearDepthTexName = "_LianLinearDepthTex";
        public const string HalfResDepthName = "_LianHalfResDepth";
        public const string SSAOTexName = "_LianSSAOTex";
        public const string CapsuleAOTexName = "_LianCapsuleAOTex";
        public const string ShadowAOTexName = "_LianShadowAOTex";
        public const string SkinDiffuseTexName = "_LianSkinDiffuseTex";
        public const string SkinProfileTexName = "_LianSkinProfileTex";
        public const string SSSTexName = "_LianSSSTex";
        public const string DoFBufferTexName = "_LianDoFBufferTex";
        public const string DoFHalfTexName = "_LianDoFHalfTex";
        public const string TAAHistoryTexName = "_LianTAAHistoryTex";
        public const string TAAHistoryPrevTexName = "_LianTAAHistoryPrevTex";
        public const string DoFResultTexName = "_LianDoFResultTex";

        // ---------------- StructuredBuffer 契约名(dump 数组,不得改名) ----------------
        public const string LightPosTypeName = "_LianLightPosType";      // float4[20] — _9._m0
        public const string LightSpotAttenName = "_LianLightSpotAtten";  // float4[20] — _9._m1
        public const string LightColorName = "_LianLightColor";          // float4[20] — _9._m3
        public const string LightDistAttenName = "_LianLightDistAtten";  // float4[20] — _9._m4
        public const string LightSpotDirName = "_LianLightSpotDir";      // float4[20] — _9._m5
        public const string LightShadowSelName = "_LianLightShadowSel";  // float4[20] — _9._m6
        public const string LightRectsName = "_LianLightRects";          // float4[50] — _8._m0(xy=rectMin, zw=rectMax, tile 空间)
        public const string CapsuleShapesName = "_LianCapsuleShapes";    // float4[64] — _20._m5(偶槽 center+radius, 奇槽 dir+length)

        // ---------------- 全局量契约名 ----------------
        public const string TileScaleBiasName = "_LianTileScaleBias";        // pass 2: xy=偏移, zw=缩放
        public const string LightCountName = "_LianLightCount";              // pass 2
        public const string WorldToShadowName = "_LianWorldToShadow";        // float4[20] 行序 — _34._m0
        public const string CascadeSphereRadiiSqName = "_LianCascadeSphereRadiiSq";  // _34._m8
        public const string CascadeClipDistancesName = "_LianCascadeClipDistances";  // _34._m9
        public const string CascadeCenter0Name = "_LianCascadeCenter0";      // _34._m4
        public const string CascadeCenter1Name = "_LianCascadeCenter1";      // _34._m5
        public const string CascadeCenter2Name = "_LianCascadeCenter2";      // _34._m6
        public const string ShadowMapTexelName = "_LianShadowMapTexel";      // _34._m17: xy=1/size, zw=size
        public const string CascadeDitherName = "_LianCascadeDither";        // float[16] — _34._m3
        public const string SpecialWorldToShadowName = "_LianSpecialWorldToShadow"; // float4[4] 行序 — _23._m2 / _20._m0
        public const string ShadowMapSizeName = "_LianShadowMapSize";        // 标量 2048

        // capsule AO(pass 7/15)
        public const string CapsuleAOCountName = "_LianCapsuleAOCount";        // _20._m0.x
        public const string CapsuleAOErrorRadiusName = "_LianCapsuleAOErrorRadius";  // _20._m2
        public const string CapsuleAOTileScaleName = "_LianCapsuleAOTileScale";      // _20._m3
        public const string CapsuleAONormDistName = "_LianCapsuleAONormDist";        // _20._m4
        public const string CapsuleAOPowName = "_LianCapsuleAOPow";                  // _20._m7
        public const string CapsuleAOConeAngleName = "_LianCapsuleAOConeAngle";      // _20._m9

        // SSAO(pass 9)
        public const string SSAOScaleBiasName = "_LianSSAOScaleBias";   // _14._m1
        public const string SSAOTexelSizeName = "_LianSSAOTexelSize";   // _14._m2.zw
        public const string SSAOParamsName = "_LianSSAOParams";         // _14._m5 (baseRadius, angleBias, distScale, ?)
        public const string SSAOStrengthName = "_LianSSAOStrength";     // _14._m6.y

        // 其它
        public const string FogNoiseParamsName = "_LianFogNoiseParams"; // pass 1 的 _14._m55 等(见 LianFogNoise.shader)

        // ---------------- PropertyID 缓存 ----------------
        public static readonly int FogNoiseTexId = Shader.PropertyToID(FogNoiseTexName);
        public static readonly int TileLightIndexTexId = Shader.PropertyToID(TileLightIndexTexName);
        public static readonly int ShadowAtlasTexId = Shader.PropertyToID(ShadowAtlasTexName);
        public static readonly int NormalTexId = Shader.PropertyToID(NormalTexName);
        public static readonly int MotionVectorTexId = Shader.PropertyToID(MotionVectorTexName);
        public static readonly int CascadeShadowTexId = Shader.PropertyToID(CascadeShadowTexName);
        public static readonly int LinearDepthTexId = Shader.PropertyToID(LinearDepthTexName);
        public static readonly int HalfResDepthId = Shader.PropertyToID(HalfResDepthName);
        public static readonly int SSAOTexId = Shader.PropertyToID(SSAOTexName);
        public static readonly int CapsuleAOTexId = Shader.PropertyToID(CapsuleAOTexName);
        public static readonly int ShadowAOTexId = Shader.PropertyToID(ShadowAOTexName);
        public static readonly int SkinDiffuseTexId = Shader.PropertyToID(SkinDiffuseTexName);
        public static readonly int SkinProfileTexId = Shader.PropertyToID(SkinProfileTexName);
        public static readonly int SSSTexId = Shader.PropertyToID(SSSTexName);
        public static readonly int DoFBufferTexId = Shader.PropertyToID(DoFBufferTexName);
        public static readonly int DoFHalfTexId = Shader.PropertyToID(DoFHalfTexName);
        public static readonly int TAAHistoryTexId = Shader.PropertyToID(TAAHistoryTexName);
        public static readonly int TAAHistoryPrevTexId = Shader.PropertyToID(TAAHistoryPrevTexName);
        public static readonly int DoFResultTexId = Shader.PropertyToID(DoFResultTexName);
    }

    /// <summary>
    /// 一个附加光的着色数据,与 dump `_9._m0.._m6[20]` 六个数组一一对应。
    /// </summary>
    [Serializable]
    public struct LianLightData
    {
        public Vector4 posType;     // _9._m0[i]: pos.xyz, w=0 方向光(lightDir=pos.xyz)/ w=1 位置光(lightDir=pos-posWS)
        public Vector4 spotAtten;   // _9._m1[i]: (spotScale, spotBias, 0, 0), 角度衰减 = saturate(SdotL·x + y)²
        public Vector4 color;       // _9._m3[i]: 颜色 rgb
        public Vector4 distAtten;   // _9._m4[i]: (x, y, z), 距离衰减 = saturate(lenSq·y + z) / (lenSq·x + 1)
        public Vector4 spotDir;     // _9._m5[i]: 聚光方向 xyz
        public Vector4 shadowSel;   // _9._m6[i]: 阴影选择权重 dot(_LianShadowAOTex 采样, w)(r=级联, g=soft, b=空, a=AO)
    }

    /// <summary>
    /// 一个胶囊遮挡体,与 dump `_20._m5[64]` 两槽一组对应:偶槽 center+radius,奇槽 dir+length。
    /// </summary>
    [Serializable]
    public struct CapsuleShape
    {
        public Vector4 centerRadius;  // 偶槽 2i: center.xyz, radius.w
        public Vector4 dirLength;     // 奇槽 2i+1: dir.xyz(归一化), length.w(轴长)
    }

    /// <summary>
    /// 级联阴影数据:渲染矩阵 + 采样全局量(dump `_34` 各字段)。
    /// </summary>
    public struct LianCascadeData
    {
        public Matrix4x4[] view;          // [4] 切片视图矩阵(渲染阴影 atlas 用)
        public Matrix4x4[] proj;          // [4] 切片投影矩阵(已做 reversed-z 处理)
        public Matrix4x4[] worldToShadow; // [4] 采样矩阵 = proj * view
        public Vector4 sphereRadiiSq;     // _34._m8 = (r0², r1², r2², r3²)
        public Vector4 clipDistances;     // _34._m9 = (r0, r1, r2, shadowDistance)
        public Vector3 center0, center1, center2;  // _34._m4/_m5/_m6 世界空间球心
        public Vector2 texelSize;         // 1/shadowMapSize
        public int shadowMapSize;
    }

    /// <summary>
    /// 灯光/胶囊体收集与级联矩阵计算(挂在 LianRenderFeature 每帧调用)。
    /// </summary>
    public static class LianFrameDataUtils
    {
        /// <summary>
        /// 收集场景内所有 LianLight 组件,打包到六个着色数组 + tile 矩形数组。
        /// rects[i] = 灯光世界 xz 包围矩形(±range)在 tile 网格坐标(xy=min, zw=max);
        /// 方向光不参与 tile 剔除(rect 置 0 → 永不相交)。灯光超过上限时截断。
        /// </summary>
        public static int CollectLights(Vector4[] posType, Vector4[] spotAtten, Vector4[] color,
            Vector4[] distAtten, Vector4[] spotDir, Vector4[] shadowSel, Vector4[] rects,
            Vector2 gridOrigin, float tileWorldSize)
        {
            Array.Clear(posType, 0, posType.Length);
            Array.Clear(spotAtten, 0, spotAtten.Length);
            Array.Clear(color, 0, color.Length);
            Array.Clear(distAtten, 0, distAtten.Length);
            Array.Clear(spotDir, 0, spotDir.Length);
            Array.Clear(shadowSel, 0, shadowSel.Length);
            Array.Clear(rects, 0, rects.Length);

            var lights = UnityEngine.Object.FindObjectsOfType<LianLight>();
            int count = Mathf.Min(lights.Length, LianFrameData.MaxShadingLights);
            float invTile = 1f / Mathf.Max(tileWorldSize, 1e-4f);
            for (int i = 0; i < count; ++i)
            {
                LianLight l = lights[i];
                Light unityLight = l.GetComponent<Light>();
                LianLightData d = l.GetData(unityLight);
                posType[i] = d.posType;
                spotAtten[i] = d.spotAtten;
                color[i] = d.color;
                distAtten[i] = d.distAtten;
                spotDir[i] = d.spotDir;
                shadowSel[i] = d.shadowSel;

                // tile 矩形(仅位置光/聚光)
                if (unityLight != null && unityLight.type != LightType.Directional)
                {
                    float range = Mathf.Max(unityLight.range, 0.01f);
                    Vector3 p = l.transform.position;
                    float minX = (p.x - range - gridOrigin.x) * invTile;
                    float minZ = (p.z - range - gridOrigin.y) * invTile;
                    float maxX = (p.x + range - gridOrigin.x) * invTile;
                    float maxZ = (p.z + range - gridOrigin.y) * invTile;
                    rects[i] = new Vector4(minX, minZ, maxX, maxZ);
                }
            }
            return count;
        }

        /// <summary>
        /// 收集场景内所有 LianCapsuleAO 组件到 64 槽数组(偶槽 center+radius, 奇槽 dir+length)。
        /// </summary>
        public static int CollectCapsules(Vector4[] shapes)
        {
            Array.Clear(shapes, 0, shapes.Length);
            var capsules = UnityEngine.Object.FindObjectsOfType<LianCapsuleAO>();
            int count = Mathf.Min(capsules.Length, LianFrameData.MaxCapsuleGroups);
            for (int i = 0; i < count; ++i)
            {
                CapsuleShape s = capsules[i].GetShape();
                shapes[i * 2] = s.centerRadius;
                shapes[i * 2 + 1] = s.dirLength;
            }
            return count;
        }

        /// <summary>
        /// 4×4 Bayer 抖动阈值(dump `_34._m3[16]`):标准 Bayer 顺序 /16。
        /// </summary>
        public static readonly float[] CascadeDither =
        {
            0f / 16f, 8f / 16f, 2f / 16f, 10f / 16f,
            12f / 16f, 4f / 16f, 14f / 16f, 6f / 16f,
            3f / 16f, 11f / 16f, 1f / 16f, 9f / 16f,
            15f / 16f, 7f / 16f, 13f / 16f, 5f / 16f,
        };

        /// <summary>
        /// 计算级联阴影数据(计划锁定的 glue,算法见计划"阴影数据"节):
        /// center_i = cameraPos + cameraForward·(split_{i-1}+split_i)/2,radius_i = split_i;
        /// view = LookAt(center - lightDir·radius, center, up),proj = Ortho(-r, r, -r, r, 0.01, 2r);
        /// worldToShadow = proj·view(proj 按 SystemInfo.usesReversedZBuffer 翻转,与 URP ShadowUtils.GetShadowTransform 一致)。
        /// 切片 3 仅在 specialLightDir 非空时填充(特殊光)。
        /// </summary>
        public static LianCascadeData ComputeCascadeData(Vector3 cameraPos, Vector3 cameraForward,
            Vector3 lightDir, float shadowDistance, Vector3 splits, int shadowMapSize,
            Vector3? specialLightDir = null)
        {
            var data = new LianCascadeData
            {
                view = new Matrix4x4[4],
                proj = new Matrix4x4[4],
                worldToShadow = new Matrix4x4[4],
                shadowMapSize = shadowMapSize,
                texelSize = new Vector2(1f / shadowMapSize, 1f / shadowMapSize),
            };

            float r0 = splits.x * shadowDistance;
            float r1 = splits.y * shadowDistance;
            float r2 = splits.z * shadowDistance;
            float r3 = shadowDistance;

            data.sphereRadiiSq = new Vector4(r0 * r0, r1 * r1, r2 * r2, r3 * r3);
            data.clipDistances = new Vector4(r0, r1, r2, r3);

            data.center0 = cameraPos + cameraForward * (r0 * 0.5f);
            data.center1 = cameraPos + cameraForward * ((r0 + r1) * 0.5f);
            data.center2 = cameraPos + cameraForward * ((r1 + r2) * 0.5f);

            Vector3 up = Mathf.Abs(Vector3.Dot(lightDir, Vector3.up)) > 0.99f ? Vector3.forward : Vector3.up;
            BuildSlice(ref data, 0, data.center0, r0, lightDir, up);
            BuildSlice(ref data, 1, data.center1, r1, lightDir, up);
            BuildSlice(ref data, 2, data.center2, r2, lightDir, up);
            if (specialLightDir.HasValue)
                BuildSlice(ref data, 3, cameraPos + cameraForward * ((r2 + r3) * 0.5f), r3, specialLightDir.Value, up);

            return data;
        }

        static void BuildSlice(ref LianCascadeData data, int index, Vector3 center, float radius,
            Vector3 lightDir, Vector3 up)
        {
            // 阴影相机置于光源侧(center + lightDir·r),沿 −lightDir 看向 center。
            // 视图矩阵用经典 gluLookAt(GL 约定,视空间沿 −z 向前,与 Matrix4x4.Ortho 一致;
            // TRS·inverse 给出 Unity 相机约定(+z 向前),与 Ortho 组合会裁剪掉全部几何)。
            Vector3 eye = center + lightDir * radius;
            Vector3 fwd = center - eye;
            if (fwd.sqrMagnitude < 1e-6f)
                fwd = -lightDir;
            fwd.Normalize();
            Vector3 s = Vector3.Cross(up, fwd);
            if (s.sqrMagnitude < 1e-6f)
                s = Vector3.Cross(Vector3.forward, fwd);
            s.Normalize();
            Vector3 u = Vector3.Cross(fwd, s);

            var view = new Matrix4x4();
            view.SetRow(0, new Vector4(s.x, s.y, s.z, -Vector3.Dot(s, eye)));
            view.SetRow(1, new Vector4(u.x, u.y, u.z, -Vector3.Dot(u, eye)));
            view.SetRow(2, new Vector4(-fwd.x, -fwd.y, -fwd.z, Vector3.Dot(fwd, eye)));
            view.SetRow(3, new Vector4(0f, 0f, 0f, 1f));
            data.view[index] = view;

            Matrix4x4 proj = Matrix4x4.Ortho(-radius, radius, -radius, radius, 0.01f, 2f * radius);
            if (SystemInfo.usesReversedZBuffer)
            {
                proj.m20 = -proj.m20;
                proj.m21 = -proj.m21;
                proj.m22 = -proj.m22;
                proj.m23 = -proj.m23;
            }
            data.proj[index] = proj;
            // 采样矩阵含纹理 scale+bias(与 URP ShadowUtils.GetShadowTransform 一致):
            // dump pass 6 直接对 shadowCS.xy × 2048 取像素坐标,要求矩阵已映射到 [0,1]
            var texScaleBias = Matrix4x4.identity;
            texScaleBias.m00 = 0.5f;
            texScaleBias.m11 = 0.5f;
            texScaleBias.m22 = 0.5f;
            texScaleBias.m03 = 0.5f;
            texScaleBias.m13 = 0.5f;
            texScaleBias.m23 = 0.5f;
            data.worldToShadow[index] = texScaleBias * proj * data.view[index];
        }

        /// <summary>
        /// 把级联矩阵写入 `_LianWorldToShadow` 的 20 行槽位(4 行 × 4 级联 + 4 备用),与 dump `_34._m0[cascade<<2 + row]` 访问一致。
        /// </summary>
        public static void FillWorldToShadowRows(Vector4[] rows, LianCascadeData data)
        {
            Array.Clear(rows, 0, rows.Length);
            for (int c = 0; c < 4; ++c)
            {
                Matrix4x4 m = data.worldToShadow[c];
                rows[c * 4 + 0] = m.GetRow(0);
                rows[c * 4 + 1] = m.GetRow(1);
                rows[c * 4 + 2] = m.GetRow(2);
                rows[c * 4 + 3] = m.GetRow(3);
            }
        }
    }
}
