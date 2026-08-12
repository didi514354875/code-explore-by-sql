using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;
using ShaolvQianxian2;

/// <summary>
/// 编译验证 + 离屏渲染验证:导入 ShaolvQianxian2.shader 强制编译全部 pass(CompileAll),
/// 新建空场景挂材质/灯光/相机/ShaolvRenderFeature 渲染截图(RenderTest)。
/// 已知环境限制(Tuanjie batchmode 离屏渲染):URP 附加光数据不填充(_AdditionalLightsCount=0)、
/// 主光阴影采样不生效(Lit 基线同)、顶点流插值异常;阴影/灯光输入数据(矩阵/贴图/球/尺寸)已在诊断确认有效。
/// 运行时(编辑器播放/构建)不受这些限制。
/// </summary>
public static class ShaolvVerification
{
    const string ScenePath = "Assets/Scenes/ShaolvPipelineTest.unity";
    const string OutDir = "D:/TProj/NPRTest/verify";
    const string ShaderName = "ShaolvQianxian2/Character";
    const string MatPath = "Assets/Materials/ShaolvTest.mat";

    public static void CompileAll()
    {
        AssetDatabase.ImportAsset("Assets/shaolvqianxian2/ShaolvQianxian2.shader",
            ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);
        AssetDatabase.ImportAsset("Assets/shaolvqianxian2/ShaolvInput.hlsl",
            ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);
        AssetDatabase.ImportAsset("Assets/shaolvqianxian2/ShaolvVertex.hlsl",
            ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);
        AssetDatabase.ImportAsset("Assets/shaolvqianxian2/ShaolvLighting.hlsl",
            ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);

        Shader shader = Shader.Find(ShaderName);
        if (shader == null)
        {
            Debug.LogError("[ShaolvVerification] Shader not found after import");
            return;
        }

        Material mat = new Material(shader);
        for (int p = 0; p < shader.passCount; p++)
        {
            ShaderUtil.CompilePass(mat, p, true);
        }
        Object.DestroyImmediate(mat);
        Debug.Log($"[ShaolvVerification] Compiled {shader.passCount} passes (errors logged above, if any)");
    }

    public static void RenderTest()
    {
        AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        // 测试材质(目标 shader;默认白纹理会让 metallic=1/roughness=1,测试用灰参数贴图 + bump 等价)
        Material charMat = AssetDatabase.LoadAssetAtPath<Material>(MatPath);
        if (charMat == null)
        {
            charMat = new Material(Shader.Find(ShaderName));
            AssetDatabase.CreateAsset(charMat, MatPath);
        }
        charMat.SetTexture("_PBRParamTex", Texture2D.grayTexture);   // roughness 0.5, metallic 0.5
        charMat.SetFloat("_ToonOn", 0f);
        var bumpTex = new Texture2D(4, 4, TextureFormat.RGBA32, false);
        var bumpPixels = new Color32[16];
        for (int i = 0; i < 16; i++) bumpPixels[i] = new Color32(128, 128, 255, 255);
        bumpTex.SetPixels32(bumpPixels);
        bumpTex.Apply();
        charMat.SetTexture("_NormalTex", bumpTex);

        // 地面(也用目标 shader)
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "Ground";
        ground.GetComponent<MeshRenderer>().sharedMaterial = charMat;

        // 角色(球体)
        var character = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        character.name = "Character";
        character.transform.position = new Vector3(0f, 1f, 3f);
        character.GetComponent<MeshRenderer>().sharedMaterial = charMat;

        // 主方向光(开阴影,验证级联)
        var sunGO = new GameObject("Sun");
        var sun = sunGO.AddComponent<Light>();
        sun.type = LightType.Directional;
        sun.shadows = LightShadows.Soft;
        sun.color = new Color(1f, 0.95f, 0.9f);
        sunGO.transform.rotation = Quaternion.Euler(50f, -30f, 0f);

        // 附加点光(验证附加光循环)
        var pointGO = new GameObject("PointLight");
        var point = pointGO.AddComponent<Light>();
        point.type = LightType.Point;
        point.range = 8f;
        point.color = new Color(0.3f, 0.5f, 1f);
        point.intensity = 3f;
        pointGO.transform.position = new Vector3(2f, 1.5f, 2f);

        // 相机
        var camGO = new GameObject("Main Camera");
        camGO.tag = "MainCamera";
        var cam = camGO.AddComponent<Camera>();
        camGO.AddComponent<UniversalAdditionalCameraData>();
        cam.transform.position = new Vector3(0f, 1.5f, -4f);
        cam.transform.rotation = Quaternion.identity;

        var feature = EnsureFeature();

        // 渲染三帧:基准 / 关级联阴影 / 关附加光
        Directory.CreateDirectory(OutDir);
        string path = OutDir + "/shaolv_test.png";
        Capture(cam, path);
        Debug.Log("[ShaolvVerification] 已保存 " + path);

        charMat.SetFloat("_CascadeShadowOn", 0f);
        string pathNoShadow = OutDir + "/shaolv_test_noshadow.png";
        Capture(cam, pathNoShadow);
        charMat.SetFloat("_CascadeShadowOn", 1f);
        Debug.Log("[ShaolvVerification] 已保存 " + pathNoShadow);

        point.intensity = 0f;
        string pathNoAddi = OutDir + "/shaolv_test_noaddi.png";
        Capture(cam, pathNoAddi);
        point.intensity = 3f;
        Debug.Log("[ShaolvVerification] 已保存 " + pathNoAddi);

        // MRT 内容验证:统计法线遮罩 RT 与屏幕偏移 RT 的非零像素
        if (feature != null && feature.normalMaskRT != null)
        {
            int nonZeroN = CountNonZero(feature.normalMaskRT);
            int nonZeroS = CountNonZero(feature.screenOffsetRT);
            Debug.Log($"[ShaolvVerification] MRT 内容: normalMask 非零像素={nonZeroN}/{feature.normalMaskRT.width * feature.normalMaskRT.height} " +
                      $"screenOffset 非零像素={nonZeroS}");
        }
        else
        {
            Debug.Log($"[ShaolvVerification] MRT 读取失败 feature={(feature != null)} rt={(feature != null ? feature.normalMaskRT != null : false)}");
        }

        // 渲染后阴影输入诊断(证明 URP 阴影数据完整,供运行时使用)
        Matrix4x4 m0 = Shader.GetGlobalMatrix("_MainLightWorldToShadow");
        Texture shadowTex = Shader.GetGlobalTexture("_MainLightShadowmapTexture");
        Debug.Log($"[ShaolvVerification] shadowTex={(shadowTex != null ? shadowTex.width + "x" + shadowTex.height : "null")} " +
                  $"_MainLightWorldToShadow[0].m00={m0.m00} _AdditionalLightsCount.x={Shader.GetGlobalVector("_AdditionalLightsCount").x}");

        EditorSceneManager.SaveScene(scene, ScenePath);
        Debug.Log("[ShaolvVerification] 场景已保存 " + ScenePath);
    }

    /// <summary>在 pipeline 实际使用的 rendererData 上确保存在 ShaolvRenderFeature。</summary>
    static ShaolvRenderFeature EnsureFeature()
    {
        ScriptableRendererData rendererData = null;
        var pipelineAsset = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
        if (pipelineAsset != null)
        {
            var field = typeof(UniversalRenderPipelineAsset).GetField("m_RendererDataList",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            if (field != null && field.GetValue(pipelineAsset) is ScriptableRendererData[] list && list.Length > 0)
            {
                var idxField = typeof(UniversalRenderPipelineAsset).GetField("m_DefaultRendererIndex",
                    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
                int idx = idxField != null ? (int)idxField.GetValue(pipelineAsset) : 0;
                idx = Mathf.Clamp(idx, 0, list.Length - 1);
                rendererData = list[idx];
            }
        }
        if (rendererData == null)
        {
            Debug.LogError("[ShaolvVerification] 无法获取 pipeline rendererData");
            return null;
        }
        Debug.Log($"[ShaolvVerification] 使用 rendererData: {rendererData.name}");

        rendererData.rendererFeatures.RemoveAll(f => f == null);
        foreach (var f in rendererData.rendererFeatures)
        {
            if (f is ShaolvRenderFeature sf)
                return sf;
        }
        var feature = ScriptableObject.CreateInstance<ShaolvRenderFeature>();
        feature.name = "ShaolvRenderFeature";
        AssetDatabase.AddObjectToAsset(feature, rendererData);   // 必须持久化为 sub-asset
        rendererData.rendererFeatures.Add(feature);
        EditorUtility.SetDirty(rendererData);
        AssetDatabase.SaveAssets();
        // 强制 URP 重建 renderer(isInvalidated 为 internal,用反射)
        var prop = typeof(ScriptableRendererData).GetProperty("isInvalidated",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        prop?.SetValue(rendererData, true);
        Debug.Log("[ShaolvVerification] 已添加 ShaolvRenderFeature 并标记 renderer invalidated");
        return feature;
    }

    static int CountNonZero(RenderTexture rt)
    {
        var readback = new RenderTexture(rt.width, rt.height, 0, RenderTextureFormat.ARGB32);
        Graphics.Blit(rt, readback);
        var tex2d = new Texture2D(rt.width, rt.height, TextureFormat.RGBA32, false);
        RenderTexture.active = readback;
        tex2d.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        tex2d.Apply();
        RenderTexture.active = null;
        int nonZero = 0;
        Color32[] px = tex2d.GetPixels32();
        foreach (var p in px)
        {
            if (p.r != 0 || p.g != 0 || p.b != 0 || p.a != 0)
                nonZero++;
        }
        Object.DestroyImmediate(tex2d);
        readback.Release();
        return nonZero;
    }

    static void Capture(Camera cam, string path)
    {
        RenderTexture rt = new RenderTexture(640, 360, 24, RenderTextureFormat.ARGB32);
        RenderTexture oldTarget = cam.targetTexture;
        cam.targetTexture = rt;
        cam.Render();
        cam.targetTexture = oldTarget;

        RenderTexture.active = rt;
        var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        tex.Apply();
        RenderTexture.active = null;
        File.WriteAllBytes(path, tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
        rt.Release();
    }
}
