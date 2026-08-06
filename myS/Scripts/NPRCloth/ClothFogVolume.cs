using UnityEngine;

namespace NPRCloth
{
    /// <summary>
    /// 雾全局参数(挂在任意对象上,每帧写入 ClothFog CBUFFER 对应的全局常量)。
    /// 默认全 0 = 无雾。LUT 雾需要:材质开 _FOG_LUT_3D + lutParams4.z > 0 + _FogLUT3D 纹理。
    /// </summary>
    [DisallowMultipleComponent]
    public class ClothFogVolume : MonoBehaviour
    {
        [Header("解析高度雾")]
        public float density = 0f;             // cb0[136].w
        public float startDistance = 0f;       // cb0[134].w
        public float startHeight = 0f;         // cb0[133].w
        public float endHeight = 0f;           // cb0[135].w
        public float heightFalloff = 1f;       // cb0[131].w
        public Vector3 lightDir = Vector3.up;  // cb0[136].xyz
        public Color baseColor = Color.black;  // cb0[133].xyz
        public Color scatteringScale = Color.black; // cb0[131].xyz
        public Color rayleighColor = Color.black;   // cb0[134].xyz
        public Color mieColor = Color.black;        // cb0[132].xyz
        public float mieG = 0f;                     // cb0[132].w
        public Color finalColorScale = Color.white; // cb0[135].xyz

        [Header("LUT 参数(默认 0 = 不启用 LUT)")]
        public Vector4 lutParams0 = Vector4.zero;   // cb0[137] 相机高度带指数参数
        public Vector4 lutParams1 = Vector4.zero;   // cb0[138] 距离积分区间
        public Vector4 lutParams2 = Vector4.zero;   // cb0[139] xyz 雾色 w 因子下限
        public Vector4 lutParams3 = Vector4.zero;   // cb0[140] 第二高度带
        public Vector4 lutParams4 = Vector4.zero;   // cb0[141] z>0 启用 LUT, w=1/forwardFactor 强度
        public Vector4 lutParams5 = Vector4.zero;   // cb0[142] log 变换
        public Vector4 lutParams6 = Vector4.zero;   // cb0[143] uv 缩放
        public Vector4 lutParams7 = Vector4.zero;   // cb0[144] 混合阈值距离
        public Vector4 lutParams8 = Vector4.zero;   // cb0[145] hash 抖动强度

        void OnEnable()
        {
            // 雾开:置 _FogEnabled = 0(对应原始 cb0[171].w = 0);对 Cloth.shader 无影响(其雾无门,照旧恒算恒等)
            Shader.SetGlobalFloat("_FogEnabled", 0f);
        }

        void OnDisable()
        {
            // 雾关:ClothFrameData 每帧会把 _FogEnabled 重置回 1,这里立即关避免残留一帧
            Shader.SetGlobalFloat("_FogEnabled", 1f);
        }

        void Update()
        {
            Shader.SetGlobalFloat("_FogEnabled", 0f);
            Shader.SetGlobalFloat("_FogDensity", density);
            Shader.SetGlobalFloat("_FogStartDistance", startDistance);
            Shader.SetGlobalFloat("_FogStartHeight", startHeight);
            Shader.SetGlobalFloat("_FogEndHeight", endHeight);
            Shader.SetGlobalFloat("_FogHeightFalloff", heightFalloff);
            Shader.SetGlobalVector("_FogLightDir", new Vector4(lightDir.x, lightDir.y, lightDir.z, density));
            Shader.SetGlobalVector("_FogBaseColor", new Vector4(baseColor.r, baseColor.g, baseColor.b, startHeight));
            Shader.SetGlobalVector("_FogScatteringScale", new Vector4(scatteringScale.r, scatteringScale.g, scatteringScale.b, heightFalloff));
            Shader.SetGlobalVector("_FogRayleighColor", new Vector4(rayleighColor.r, rayleighColor.g, rayleighColor.b, startDistance));
            Shader.SetGlobalVector("_FogMieColor", new Vector4(mieColor.r, mieColor.g, mieColor.b, mieG));
            Shader.SetGlobalVector("_FogFinalColorScale", new Vector4(finalColorScale.r, finalColorScale.g, finalColorScale.b, endHeight));
            Shader.SetGlobalVector("_FogLUTParams0", lutParams0);
            Shader.SetGlobalVector("_FogLUTParams1", lutParams1);
            Shader.SetGlobalVector("_FogLUTParams2", lutParams2);
            Shader.SetGlobalVector("_FogLUTParams3", lutParams3);
            Shader.SetGlobalVector("_FogLUTParams4", lutParams4);
            Shader.SetGlobalVector("_FogLUTParams5", lutParams5);
            Shader.SetGlobalVector("_FogLUTParams6", lutParams6);
            Shader.SetGlobalVector("_FogLUTParams7", lutParams7);
            Shader.SetGlobalVector("_FogLUTParams8", lutParams8);
        }
    }
}
