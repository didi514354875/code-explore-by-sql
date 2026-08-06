using System.Collections.Generic;
using UnityEngine;

namespace NPRCloth
{
    /// <summary>
    /// 材质回退兜底:Cloth/Skin/Face 三个 NPR shader 的美术纹理(ramp/LUT/雨/MatCap/阴影/体积/雾)未赋值时
    /// 补 1×1 白纹理,并同步 _Cull 与 _DOUBLE_SIDED 关键字。静态缓存,不产生资产。
    /// </summary>
    public static class ClothMaterialSetup
    {
        public const string ShaderName = "NPRCloth/Cloth";
        public const string SkinShaderName = "NPRCharacter/Skin";
        public const string FaceShaderName = "NPRCharacter/Face";

        static readonly string[] k_ShaderNames = { ShaderName, SkinShaderName, FaceShaderName };

        // Cloth 专用(含 Spec LUT / 雨贴图)
        static readonly string[] k_ClothFallbackProps =
        {
            "_RampTex", "_SpecStylizedLUT", "_RainDropTex", "_RainFlowTex", "_MatCapTex",
            "_CharacterShadowTex", "_VolumeIndex3D", "_VolumeLight3D", "_VolumeLightLowFreq3D", "_FogLUT3D"
        };
        // Skin:无 Spec LUT/雨贴图,有颜色分级 LUT
        static readonly string[] k_SkinFallbackProps =
        {
            "_RampTex", "_ColorGradeLUT", "_MatCapTex",
            "_CharacterShadowTex", "_VolumeIndex3D", "_VolumeLight3D", "_VolumeLightLowFreq3D", "_FogLUT3D"
        };
        // Face:Skin + 雨贴图 + 脸部控制/SDF
        static readonly string[] k_FaceFallbackProps =
        {
            "_RampTex", "_ColorGradeLUT", "_RainDropTex", "_RainFlowTex", "_MatCapTex",
            "_CharacterShadowTex", "_VolumeIndex3D", "_VolumeLight3D", "_VolumeLightLowFreq3D", "_FogLUT3D",
            "_FaceControlTex", "_FaceSDFTex"
        };

        static Texture2D s_WhiteTexture;
        static readonly HashSet<Material> s_Handled = new HashSet<Material>();

        /// <summary>shader 是否属于 NPR 角色三件套(Cloth/Skin/Face)。</summary>
        public static bool IsCharacterShader(Shader shader)
        {
            if (shader == null) return false;
            foreach (var name in k_ShaderNames)
                if (shader.name == name) return true;
            return false;
        }

        static string[] GetFallbackProps(string shaderName)
        {
            if (shaderName == SkinShaderName) return k_SkinFallbackProps;
            if (shaderName == FaceShaderName) return k_FaceFallbackProps;
            return k_ClothFallbackProps;
        }

        static Texture2D whiteTexture
        {
            get
            {
                if (s_WhiteTexture == null)
                {
                    s_WhiteTexture = new Texture2D(1, 1, TextureFormat.RGBA32, false, true);
                    s_WhiteTexture.SetPixel(0, 0, Color.white);
                    s_WhiteTexture.Apply();
                    s_WhiteTexture.hideFlags = HideFlags.DontSave;
                }
                return s_WhiteTexture;
            }
        }

        /// <summary>遍历场景中所有使用 Cloth/Skin/Face shader 的材质并补齐回退(幂等,按材质实例去重)。</summary>
        public static void EnsureFallbacks()
        {
            var renderers = Object.FindObjectsOfType<Renderer>();
            foreach (var r in renderers)
            {
                if (r == null) continue;
                foreach (var mat in r.sharedMaterials)
                {
                    if (mat == null || mat.shader == null) continue;
                    if (!IsCharacterShader(mat.shader)) continue;
                    ApplyFallbacks(mat);
                }
            }
        }

        /// <summary>对单个材质补齐回退(编辑器/运行时均可调用)。</summary>
        public static void ApplyFallbacks(Material mat)
        {
            if (mat == null || mat.shader == null || !IsCharacterShader(mat.shader)) return;
            if (s_Handled.Contains(mat)) return;
            s_Handled.Add(mat);

            foreach (var prop in GetFallbackProps(mat.shader.name))
            {
                if (!mat.HasProperty(prop)) continue;
                if (mat.GetTexture(prop) == null)
                    mat.SetTexture(prop, whiteTexture);
            }
            // _Cull 由 _DOUBLE_SIDED 关键字决定(0=Off 双面, 2=Back)
            if (mat.HasProperty("_Cull"))
                mat.SetInt("_Cull", mat.IsKeywordEnabled("_DOUBLE_SIDED") ? 0 : 2);
        }
    }
}
