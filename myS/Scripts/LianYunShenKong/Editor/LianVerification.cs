using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;
using LianYunShenKong;

/// <summary>
/// 验证工具(临时):构建 LianPipelineTest 场景 + 配置 feature,编辑模式下逐 _debugViewRT
/// 离屏渲染截图保存 PNG。用完删除。
/// </summary>
public static class LianVerification
{
    const string ScenePath = "Assets/Scenes/LianPipelineTest.unity";
    const string OutDir = "D:/TProj/NPRTest/verify";

    static readonly int[] k_Views = { 0, 1, 2, 3, 4, 5, 6, 8, 14, 15, 16 };

    public static void BuildScene()
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        // 地面(URP Lit)
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "Ground";
        ground.GetComponent<MeshRenderer>().sharedMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit"));

        // 角色(球体,挂 LianCharacter 材质)
        var character = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        character.name = "Character";
        character.transform.position = new Vector3(0f, 1f, 3f);
        var charMat = new Material(Shader.Find("LianYunShenKong/LianCharacter"));
        character.GetComponent<MeshRenderer>().sharedMaterial = charMat;

        // 主方向光(LianLight)
        var sunGO = new GameObject("Sun");
        var sun = sunGO.AddComponent<Light>();
        sun.type = LightType.Directional;
        sun.color = new Color(1f, 0.95f, 0.9f);
        sunGO.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
        sunGO.AddComponent<LianLight>();

        // 2 个点光(LianLight)
        for (int i = 0; i < 2; ++i)
        {
            var go = new GameObject("PointLight" + i);
            var l = go.AddComponent<Light>();
            l.type = LightType.Point;
            l.range = 8f;
            l.color = i == 0 ? new Color(1f, 0.4f, 0.3f) : new Color(0.3f, 0.5f, 1f);
            go.transform.position = new Vector3(2f + i * 3f, 1.5f, 2f);
            go.AddComponent<LianLight>();
        }

        // 2 个胶囊遮挡体(LianCapsuleAO)
        for (int i = 0; i < 2; ++i)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            go.name = "Capsule" + i;
            go.transform.position = new Vector3(-2f - i * 2f, 1f, 3f);
            go.AddComponent<LianCapsuleAO>();
        }

        // 相机
        var camGO = new GameObject("Main Camera");
        camGO.tag = "MainCamera";
        var cam = camGO.AddComponent<Camera>();
        camGO.AddComponent<UniversalAdditionalCameraData>();
        cam.transform.position = new Vector3(0f, 1.5f, -4f);
        cam.transform.rotation = Quaternion.identity;

        ConfigureFeature();

        EditorSceneManager.SaveScene(scene, ScenePath);
        Debug.Log("[Lian] 场景已保存 " + ScenePath);
    }

    public static void CaptureViews()
    {
        EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        var cam = Object.FindObjectOfType<Camera>();
        if (cam == null)
        {
            Debug.LogError("[Lian] 相机未找到");
            return;
        }
        var feature = GetFeature();
        if (feature == null)
        {
            Debug.LogError("[Lian] LianRenderFeature 未找到");
            return;
        }

        Directory.CreateDirectory(OutDir);
        foreach (int view in k_Views)
        {
            LianDebugView.overrideRT = view;
            string path = OutDir + "/view_" + view + ".png";
            Capture(cam, path);
            Debug.Log("[Lian] 已保存 " + path);
        }
        ReadbackAtlasSlice0(OutDir + "/atlas_slice0.raw");
        Debug.Log("[Lian] 截图完成");
    }

    static LianRenderFeature GetFeature()
    {
        var rendererData = AssetDatabase.LoadAssetAtPath<UniversalRendererData>("Assets/Settings/URP-Balanced-Renderer.asset");
        if (rendererData == null)
            return null;
        foreach (var f in rendererData.rendererFeatures)
            if (f is LianRenderFeature)
                return (LianRenderFeature)f;
        return null;
    }

    static void ConfigureFeature()
    {
        var feature = GetFeature();
        if (feature == null)
            return;

        feature._tileLightCullingShader = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/Shaders/LianYunShenKong/LianTileLightCulling.compute");
        feature._capsuleAOShader = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/Shaders/LianYunShenKong/LianCapsuleAO.compute");

        var fogMat = AssetDatabase.LoadAssetAtPath<Material>("Assets/Materials/LianFogNoise.mat");
        if (fogMat == null)
        {
            var shader = Shader.Find("Hidden/LianYunShenKong/FogNoise");
            if (shader != null)
            {
                Directory.CreateDirectory("Assets/Materials");
                fogMat = new Material(shader);
                AssetDatabase.CreateAsset(fogMat, "Assets/Materials/LianFogNoise.mat");
            }
        }
        feature._fogNoiseMaterial = fogMat;
        feature._skinProfileTex = Texture2D.whiteTexture;
        feature._debugViewRT = 0;

        var rendererData = AssetDatabase.LoadAssetAtPath<UniversalRendererData>("Assets/Settings/URP-Balanced-Renderer.asset");
        if (rendererData != null)
            EditorUtility.SetDirty(rendererData);
        AssetDatabase.SaveAssets();
        Debug.Log("[Lian] feature 已配置");
    }

    static void ReadbackAtlasSlice0(string path)
    {
        var atlas = Shader.GetGlobalTexture("_LianShadowAtlasTex") as RenderTexture;
        if (atlas == null)
        {
            Debug.Log("[LianTrace] atlas 全局纹理未找到");
            return;
        }
        var tmp = new RenderTexture(atlas.width, atlas.height, 0, RenderTextureFormat.RFloat);
        Graphics.CopyTexture(atlas, 0, 0, tmp, 0, 0);
        var tex = new Texture2D(atlas.width, atlas.height, TextureFormat.RFloat, false);
        RenderTexture.active = tmp;
        tex.ReadPixels(new Rect(0, 0, atlas.width, atlas.height), 0, 0);
        tex.Apply();
        RenderTexture.active = null;
        tmp.Release();
        var raw = tex.GetRawTextureData();
        System.IO.File.WriteAllBytes(path, raw);
        Object.DestroyImmediate(tex);
        Debug.Log("[LianTrace] atlas 已回读 " + path + " bytes=" + raw.Length);
    }

    static void Capture(Camera cam, string path)
    {
        int w = 640, h = 360;
        var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        cam.targetTexture = rt;
        cam.Render();
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        RenderTexture.active = rt;
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();
        cam.targetTexture = null;
        RenderTexture.active = null;
        rt.Release();
        File.WriteAllBytes(path, tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
    }
}
