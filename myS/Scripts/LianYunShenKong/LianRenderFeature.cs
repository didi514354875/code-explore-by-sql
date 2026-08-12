using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace LianYunShenKong
{
    /// <summary>
    /// 恋与深空风格管线唯一 RendererFeature:按 dump 头注释 1-24 号 pass 的顺序把各 pass
    /// 挂到 URP 渲染管线上,并每帧收集灯光/胶囊体/级联阴影数据绑定为全局量。
    /// </summary>
    [DisallowMultipleComponent]
    public class LianRenderFeature : ScriptableRendererFeature
    {
        [Header("阴影")]
        [Tooltip("shadow map 尺寸(每级联)")]
        public int _shadowMapSize = 2048;
        [Tooltip("级联阴影最远距离")]
        public float _shadowDistance = 60f;
        [Tooltip("级联分割比例(相对 shadowDistance):x=0.2, y=0.5, z=1.0")]
        public Vector3 _cascadeSplits = new Vector3(0.2f, 0.5f, 1.0f);
        [Tooltip("特殊光(可选):有则渲染第 4 张 shadow map;无则 pass 6 validity 恒 false、pass 13 输出 g=1")]
        public Light _specialShadowLight;

        [Header("角色")]
        [Tooltip("参与 LianPrePass/LianSkin/LianCharacter 重绘的层")]
        public LayerMask _characterLayerMask = ~0;

        [Header("效果开关")]
        public bool _enableSSAO = true;
        public bool _enableCapsuleAO = true;
        public bool _enableSSS = true;
        public bool _enableDOF = true;
        public bool _enableTAA = true;

        [Header("tile 灯光剔除(pass 2,世界空间 XZ 网格)")]
        [Tooltip("网格边长(tile 数)")]
        public int _tileGridSize = 128;
        [Tooltip("单个 tile 的世界尺寸")]
        public float _tileWorldSize = 4f;

        [Header("SSAO(pass 9)")]
        [Tooltip("baseRadius(_14._m5.y)")]
        public float _ssaoRadius = 0.25f;
        [Tooltip("角度偏差(_14._m5.z)")]
        public float _ssaoAngleBias = 0.2f;
        [Tooltip("距离缩放(_14._m5.w,负值=距离衰减)")]
        public float _ssaoDistScale = -0.01f;
        [Tooltip("强度(_14._m6.y)")]
        public float _ssaoStrength = 0.5f;

        [Header("Capsule AO(pass 7)")]
        [Tooltip("误差半径(_20._m2)")]
        public float _capsuleErrorRadius = 0.25f;
        [Tooltip("归一化距离(_20._m4,深度打包)")]
        public float _capsuleNormDist = 200f;
        [Tooltip("AO 幂(_20._m7)")]
        public float _capsuleAOPow = 1f;
        [Tooltip("锥角弧度(_20._m9)")]
        public float _capsuleConeAngle = 0.5f;

        [Header("SSS(pass 19)")]
        [Tooltip("SSS 模糊强度(_55._m1)")]
        public float _sssScale = 2.0f;
        [Tooltip("SSS 核步数(_55._m3)")]
        public int _sssSteps = 5;

        [Header("DOF/TAA(pass 21-24)")]
        [Tooltip("对焦距离(世界单位)")]
        public float _dofFocusDistance = 6f;
        [Tooltip("对焦范围(世界单位)")]
        public float _dofFocusRange = 12f;
        [Tooltip("CoC 强度(_18._m2)")]
        public float _dofIntensity = 1f;
        [Tooltip("近焦曲线指数(_18._m3)")]
        public float _dofCurveExponent = 1f;
        [Tooltip("rgb 调暗(_18._m4)")]
        public float _dofDim = 1f;
        [Tooltip("DOF 最小模糊半径(_7._m0.x·_7._m1)")]
        public float _dofBlurRadius = 4f;
        [Tooltip("DOF 半径倍率(_7._m1)")]
        public float _dofRadiusMult = 1f;
        [Tooltip("DOF coc 偏移(_7._m3)")]
        public float _dofCocOffset = 1f;
        [Tooltip("TAA box 扩展(_20._m2)")]
        public float _taaBoxExpand = 0f;
        [Tooltip("TAA 自定义范围(_20._m3)")]
        public float _taaUseCustomRange = 0f;

        [Header("资产")]
        [Tooltip("pass 1 程序化雾 noise 材质")]
        public Material _fogNoiseMaterial;
        [Tooltip("pass 16 皮肤 profile 贴图(默认白色 1×1)")]
        public Texture2D _skinProfileTex;
        [Tooltip("pass 20 雾 LUT 3D(默认白色 1×1×1)")]
        public Texture3D _fogLUT3D;
        [Tooltip("pass 2 tile 灯光剔除 compute")]
        public ComputeShader _tileLightCullingShader;
        [Tooltip("pass 7 capsule AO compute")]
        public ComputeShader _capsuleAOShader;

        [Header("调试")]
        [Tooltip("0 = 关闭;1..N = 显示对应中间 RT(见 LianDebugView)")]
        public int _debugViewRT = 0;

        // ---------------- pass 实例 ----------------
        LianFogNoisePass m_FogNoisePass;            // pass 1
        LianTileLightCullingPass m_TileCullingPass; // pass 2
        LianShadowPass m_ShadowPass;                // pass 3/4
        LianPrePassPass m_PrePass;                  // pass 5
        LianDepthCopyPass m_DepthCopyPass;          // opaque 后深度拷贝(自持 _CameraDepthTexture)
        LianShadowScreenPass m_ShadowScreenPass;    // pass 6
        LianCapsuleAOPass m_CapsuleAOPass;          // pass 7
        LianDepthLinearPass m_DepthLinearPass;      // pass 8
        LianSSAOPass m_SSAOPass;                    // pass 9
        LianHalfDepthPass m_HalfDepthPass;          // pass 10
        LianShadowAOMergePass m_ShadowAOMergePass;  // pass 11/12/13/15
        LianSkinDiffusePass m_SkinDiffusePass;      // pass 16
        LianSSSPass m_SSSPass;                      // pass 19
        LianRenderObjectPass m_RenderObjectPass;    // pass 20
        LianDoFCoCPass m_DoFCoCPass;                // pass 21
        LianDoFPrefilterPass m_DoFPrefilterPass;    // pass 21b
        LianTAAPass m_TAAPass;                      // pass 22
        LianDoFPass m_DoFPass;                      // pass 23
        LianDoFMergePass m_DoFMergePass;            // pass 24
        LianDebugView m_DebugView;

        // ---------------- 每帧收集的数据(供各 pass Execute 读取) ----------------
        Vector4[] m_LightPosType = new Vector4[LianFrameData.MaxShadingLights];
        Vector4[] m_LightSpotAtten = new Vector4[LianFrameData.MaxShadingLights];
        Vector4[] m_LightColor = new Vector4[LianFrameData.MaxShadingLights];
        Vector4[] m_LightDistAtten = new Vector4[LianFrameData.MaxShadingLights];
        Vector4[] m_LightSpotDir = new Vector4[LianFrameData.MaxShadingLights];
        Vector4[] m_LightShadowSel = new Vector4[LianFrameData.MaxShadingLights];
        Vector4[] m_LightRects = new Vector4[LianFrameData.MaxTileLights];
        Vector4[] m_CapsuleShapes = new Vector4[LianFrameData.CapsuleSlotCount];
        Vector4[] m_WorldToShadowRows = new Vector4[20];
        Vector4[] m_SpecialWorldToShadowRows = new Vector4[4];

        ComputeBuffer m_LightPosTypeBuf;
        ComputeBuffer m_LightSpotAttenBuf;
        ComputeBuffer m_LightColorBuf;
        ComputeBuffer m_LightDistAttenBuf;
        ComputeBuffer m_LightSpotDirBuf;
        ComputeBuffer m_LightShadowSelBuf;
        ComputeBuffer m_LightRectsBuf;
        ComputeBuffer m_CapsuleShapesBuf;

        public int lightCount { get; private set; }
        public int capsuleCount { get; private set; }
        public LianCascadeData cascadeData { get; private set; }
        public bool hasSpecialShadow { get; private set; }
        public Vector3 mainLightDirection { get; private set; } = Vector3.up;

        public override void Create()
        {
            m_FogNoisePass = new LianFogNoisePass(_fogNoiseMaterial);
            m_TileCullingPass = new LianTileLightCullingPass();
            m_ShadowPass = new LianShadowPass();
            m_PrePass = new LianPrePassPass();
            m_DepthCopyPass = new LianDepthCopyPass();
            m_ShadowScreenPass = new LianShadowScreenPass();
            m_CapsuleAOPass = new LianCapsuleAOPass();
            m_DepthLinearPass = new LianDepthLinearPass();
            m_SSAOPass = new LianSSAOPass();
            m_HalfDepthPass = new LianHalfDepthPass();
            m_ShadowAOMergePass = new LianShadowAOMergePass();
            m_SkinDiffusePass = new LianSkinDiffusePass();
            m_SSSPass = new LianSSSPass();
            m_RenderObjectPass = new LianRenderObjectPass();
            m_DoFCoCPass = new LianDoFCoCPass();
            m_DoFPrefilterPass = new LianDoFPrefilterPass();
            m_TAAPass = new LianTAAPass();
            m_DoFPass = new LianDoFPass();
            m_DoFMergePass = new LianDoFMergePass();
            m_DebugView = new LianDebugView();

            // 帧调度:BeforeRenderingOpaques 按序 1..19
            // pass 1-5 不需要场景深度:保持在 opaque 之前(噪声/剔除/阴影图集/角色 MRT)。
            // 深度相关 pass 6-19 移到 opaque 之后:URP 的 CopyDepthPass 在 AfterRenderingOpaques
            // 把相机深度(地面 opaque + 角色 pre-pass 深度)拷进 _CameraDepthTexture,此时采样才有效。
            m_FogNoisePass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
            m_TileCullingPass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
            m_ShadowPass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
            m_PrePass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
            // 自持深度拷贝:opaque 之后立即执行(早于 pass 6 的 +1)
            m_DepthCopyPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            m_ShadowScreenPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 1;            m_CapsuleAOPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 2;
            m_DepthLinearPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 3;
            m_SSAOPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 4;
            m_HalfDepthPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 5;
            m_ShadowAOMergePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 6;
            m_SkinDiffusePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 7;
            m_SSSPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 8;

            // pass 20 在链尾写相机颜色(角色最终渲染)
            m_RenderObjectPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 9;

            // pass 21-24 在 post-processing 之前
            m_DoFCoCPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            m_DoFPrefilterPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            m_TAAPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            m_DoFPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            m_DoFMergePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;

            AllocateBuffers();
        }

        void AllocateBuffers()
        {
            ReleaseBuffers();
            int light = LianFrameData.MaxShadingLights;
            m_LightPosTypeBuf = new ComputeBuffer(light, 16);
            m_LightSpotAttenBuf = new ComputeBuffer(light, 16);
            m_LightColorBuf = new ComputeBuffer(light, 16);
            m_LightDistAttenBuf = new ComputeBuffer(light, 16);
            m_LightSpotDirBuf = new ComputeBuffer(light, 16);
            m_LightShadowSelBuf = new ComputeBuffer(light, 16);
            m_LightRectsBuf = new ComputeBuffer(LianFrameData.MaxTileLights, 16);
            m_CapsuleShapesBuf = new ComputeBuffer(LianFrameData.CapsuleSlotCount, 16);
        }

        void ReleaseBuffers()
        {
            if (m_LightPosTypeBuf != null) { m_LightPosTypeBuf.Release(); m_LightPosTypeBuf = null; }
            if (m_LightSpotAttenBuf != null) { m_LightSpotAttenBuf.Release(); m_LightSpotAttenBuf = null; }
            if (m_LightColorBuf != null) { m_LightColorBuf.Release(); m_LightColorBuf = null; }
            if (m_LightDistAttenBuf != null) { m_LightDistAttenBuf.Release(); m_LightDistAttenBuf = null; }
            if (m_LightSpotDirBuf != null) { m_LightSpotDirBuf.Release(); m_LightSpotDirBuf = null; }
            if (m_LightShadowSelBuf != null) { m_LightShadowSelBuf.Release(); m_LightShadowSelBuf = null; }
            if (m_LightRectsBuf != null) { m_LightRectsBuf.Release(); m_LightRectsBuf = null; }
            if (m_CapsuleShapesBuf != null) { m_CapsuleShapesBuf.Release(); m_CapsuleShapesBuf = null; }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.cameraType == CameraType.Preview)
                return;
            if (renderingData.cameraData.camera == null)
                return;

            // 本链在 BeforeRenderingOpaques 采样深度:让 URP 在 opaque 之后拷贝 _CameraDepthTexture,
            // 并保持 pass 20 之后读到的深度全局量一致
            renderingData.cameraData.requiresDepthTexture = true;

            CollectFrameData(renderingData);

            m_FogNoisePass.material = _fogNoiseMaterial;
            m_PrePass.characterLayerMask = _characterLayerMask;
            if (m_PrePass.depthOverrideMaterial == null)
            {
                var depthShader = Shader.Find("Hidden/LianYunShenKong/DepthGround");
                if (depthShader != null)
                    m_PrePass.depthOverrideMaterial = new Material(depthShader) { hideFlags = HideFlags.HideAndDontSave };
            }
            m_ShadowPass.cascadeData = cascadeData;
            m_ShadowPass.hasSpecialShadow = hasSpecialShadow;
            m_ShadowPass.lightDirection = mainLightDirection;
            m_ShadowPass.shadowMapSize = _shadowMapSize;
            m_TileCullingPass.gridSize = _tileGridSize;
            m_TileCullingPass.tileWorldSize = _tileWorldSize;
            m_TileCullingPass.computeShader = _tileLightCullingShader;
            m_CapsuleAOPass.capsuleCount = capsuleCount;
            m_CapsuleAOPass.errorRadius = _capsuleErrorRadius;
            m_CapsuleAOPass.normDist = _capsuleNormDist;
            m_CapsuleAOPass.aoPow = _capsuleAOPow;
            m_CapsuleAOPass.coneAngle = _capsuleConeAngle;
            m_CapsuleAOPass.computeShader = _capsuleAOShader;
            m_SSAOPass.baseRadius = _ssaoRadius;
            m_SSAOPass.angleBias = _ssaoAngleBias;
            m_SSAOPass.distScale = _ssaoDistScale;
            m_SSAOPass.strength = _ssaoStrength;
            m_ShadowAOMergePass.halfDepthRT = m_DepthLinearPass.halfDepthRT;
            m_ShadowAOMergePass.capsuleNormDist = _capsuleNormDist;
            // 深度拷贝 RT 注入各采样 pass(替代被重置的 _CameraDepthTexture 全局)
            m_DepthCopyPass.chainDepthRT = m_PrePass.chainDepthRT;
            m_ShadowScreenPass.sharedDepthRT = m_DepthCopyPass.output;
            m_CapsuleAOPass.sharedDepthRT = m_DepthCopyPass.output;
            m_DepthLinearPass.sharedDepthRT = m_DepthCopyPass.output;
            m_SSAOPass.sharedDepthRT = m_DepthCopyPass.output;
            m_HalfDepthPass.sharedDepthRT = m_DepthCopyPass.output;
            m_ShadowAOMergePass.sharedDepthRT = m_DepthCopyPass.output;
            m_RenderObjectPass.sharedDepthRT = m_DepthCopyPass.output;
            m_DoFCoCPass.sharedDepthRT = m_DepthCopyPass.output;
            Vector4 tileGrid = new Vector4(
                -_tileGridSize * _tileWorldSize * 0.5f,
                -_tileGridSize * _tileWorldSize * 0.5f,
                _tileWorldSize, _tileWorldSize);
            m_SkinDiffusePass.characterLayerMask = _characterLayerMask;
            m_SkinDiffusePass.halfDepthRT = m_DepthLinearPass.halfDepthRT;
            m_SkinDiffusePass.mainLightDir = mainLightDirection;
            m_SkinDiffusePass.tileGridParams = tileGrid;
            m_RenderObjectPass.characterLayerMask = _characterLayerMask;
            m_RenderObjectPass.mainLightDir = mainLightDirection;
            m_RenderObjectPass.tileGridParams = tileGrid;
            m_RenderObjectPass.fogLUT3D = _fogLUT3D;
            m_SSSPass.sssScale = _sssScale;
            m_SSSPass.steps = _sssSteps;

            // DOF/TAA 链(pass 21 → 21b → 22 → 23 → 24)
            m_DoFCoCPass.focusDistance = _dofFocusDistance;
            m_DoFCoCPass.focusRange = _dofFocusRange;
            m_DoFCoCPass.intensity = _dofIntensity;
            m_DoFCoCPass.curveExponent = _dofCurveExponent;
            m_DoFCoCPass.dim = _dofDim;
            m_DoFPrefilterPass.source = m_DoFCoCPass.output;
            m_TAAPass.boxExpand = _taaBoxExpand;
            m_TAAPass.useCustomRange = _taaUseCustomRange;
            m_DoFPass.source = m_DoFPrefilterPass.output;
            m_DoFPass.minBlurRadius = _dofBlurRadius;
            m_DoFPass.radiusMult = _dofRadiusMult;
            m_DoFPass.cocOffset = _dofCocOffset;
            m_DoFMergePass.source = m_DoFPass.output;

            m_DebugView.debugViewRT = _debugViewRT;
            m_DebugView.cameraTarget = renderer.cameraColorTargetHandle;
            m_DebugView.sources = new RTHandle[]
            {
                m_PrePass.normalRT,                 // 1  _LianNormalTex
                m_DepthLinearPass.linearRT,         // 2  _LianLinearDepthTex
                m_ShadowScreenPass.output,          // 3  _LianCascadeShadowTex
                m_ShadowAOMergePass.output,         // 4  _LianShadowAOTex
                m_SSAOPass.output,                  // 5  _LianSSAOTex
                m_CapsuleAOPass.output,             // 6  _LianCapsuleAOTex
                m_DoFCoCPass.output,                // 7  _LianDoFBufferTex
                m_PrePass.motionRT,                 // 8  _LianMotionVectorTex
                m_TileCullingPass.output,           // 9  _LianTileLightIndexTex
                m_SkinDiffusePass.output,           // 10 _LianSkinDiffuseTex
                m_SSSPass.output,                   // 11 _LianSSSTex
                m_DoFPrefilterPass.output,          // 12 _LianDoFHalfTex
                m_DoFPass.output,                   // 13 _LianDoFResultTex
                m_FogNoisePass.output,              // 14 _LianFogNoiseTex
                m_ShadowPass.shadowAtlas,           // 15 _LianShadowAtlasTex(切片 0)
                m_DepthCopyPass.output,             // 16 _LianCameraDepthCopy
            };

            // 帧调度顺序(dump 头注释 1-24)
            renderer.EnqueuePass(m_FogNoisePass);
            renderer.EnqueuePass(m_TileCullingPass);
            renderer.EnqueuePass(m_ShadowPass);
            renderer.EnqueuePass(m_PrePass);
            renderer.EnqueuePass(m_DepthCopyPass);
            renderer.EnqueuePass(m_ShadowScreenPass);
            renderer.EnqueuePass(m_CapsuleAOPass);
            renderer.EnqueuePass(m_DepthLinearPass);
            renderer.EnqueuePass(m_SSAOPass);
            renderer.EnqueuePass(m_HalfDepthPass);
            renderer.EnqueuePass(m_ShadowAOMergePass);
            renderer.EnqueuePass(m_SkinDiffusePass);
            renderer.EnqueuePass(m_SSSPass);
            renderer.EnqueuePass(m_RenderObjectPass);

            if (_enableDOF)
                renderer.EnqueuePass(m_DoFCoCPass);
            if (_enableDOF)
                renderer.EnqueuePass(m_DoFPrefilterPass);
            // TAA 依赖 21/21b 的 CoC 数据,仅在 DOF 链开启时生效
            if (_enableTAA && _enableDOF)
                renderer.EnqueuePass(m_TAAPass);
            if (_enableDOF)
                renderer.EnqueuePass(m_DoFPass);
            if (_enableDOF)
                renderer.EnqueuePass(m_DoFMergePass);

            m_DebugView.debugViewRT = _debugViewRT;
            if (LianDebugView.overrideRT != 0)
                m_DebugView.debugViewRT = LianDebugView.overrideRT;
            if (m_DebugView.debugViewRT != 0)
                renderer.EnqueuePass(m_DebugView);
        }

        /// <summary>
        /// 每帧收集灯光/胶囊体/级联数据并绑定全局量(供 pass 2/3/6/7/12/13/15/16/20 使用)。
        /// </summary>
        void CollectFrameData(RenderingData renderingData)
        {
            Vector2 gridOrigin = new Vector2(-_tileGridSize * _tileWorldSize * 0.5f, -_tileGridSize * _tileWorldSize * 0.5f);
            lightCount = LianFrameDataUtils.CollectLights(
                m_LightPosType, m_LightSpotAtten, m_LightColor,
                m_LightDistAtten, m_LightSpotDir, m_LightShadowSel,
                m_LightRects, gridOrigin, _tileWorldSize);
            capsuleCount = LianFrameDataUtils.CollectCapsules(m_CapsuleShapes);

            m_LightPosTypeBuf.SetData(m_LightPosType);
            m_LightSpotAttenBuf.SetData(m_LightSpotAtten);
            m_LightColorBuf.SetData(m_LightColor);
            m_LightDistAttenBuf.SetData(m_LightDistAtten);
            m_LightSpotDirBuf.SetData(m_LightSpotDir);
            m_LightShadowSelBuf.SetData(m_LightShadowSel);
            m_LightRectsBuf.SetData(m_LightRects);
            m_CapsuleShapesBuf.SetData(m_CapsuleShapes);

            Shader.SetGlobalBuffer(LianFrameData.LightPosTypeName, m_LightPosTypeBuf);
            Shader.SetGlobalBuffer(LianFrameData.LightSpotAttenName, m_LightSpotAttenBuf);
            Shader.SetGlobalBuffer(LianFrameData.LightColorName, m_LightColorBuf);
            Shader.SetGlobalBuffer(LianFrameData.LightDistAttenName, m_LightDistAttenBuf);
            Shader.SetGlobalBuffer(LianFrameData.LightSpotDirName, m_LightSpotDirBuf);
            Shader.SetGlobalBuffer(LianFrameData.LightShadowSelName, m_LightShadowSelBuf);
            Shader.SetGlobalBuffer(LianFrameData.LightRectsName, m_LightRectsBuf);
            Shader.SetGlobalBuffer(LianFrameData.CapsuleShapesName, m_CapsuleShapesBuf);
            Shader.SetGlobalInt(LianFrameData.LightCountName, lightCount);
            Shader.SetGlobalInt(LianFrameData.CapsuleAOCountName, capsuleCount);
            Shader.SetGlobalFloat(LianFrameData.ShadowMapSizeName, _shadowMapSize);

            // 级联阴影(主方向光)
            var cullResults = renderingData.cullResults;
            int mainLightIndex = renderingData.lightData.mainLightIndex;
            Vector3 lightDir = Vector3.up;
            bool hasMainLight = mainLightIndex >= 0 && mainLightIndex < cullResults.visibleLights.Length;
            if (hasMainLight)
            {
                Light mainLight = cullResults.visibleLights[mainLightIndex].light;
                if (mainLight != null)
                    lightDir = -mainLight.transform.forward;
            }
            mainLightDirection = lightDir;

            Vector3? specialDir = null;
            hasSpecialShadow = _specialShadowLight != null;
            if (hasSpecialShadow)
                specialDir = -_specialShadowLight.transform.forward;

            Camera cam = renderingData.cameraData.camera;
            cascadeData = LianFrameDataUtils.ComputeCascadeData(
                cam.transform.position, cam.transform.forward,
                lightDir, _shadowDistance, _cascadeSplits, _shadowMapSize, specialDir);

            LianFrameDataUtils.FillWorldToShadowRows(m_WorldToShadowRows, cascadeData);
            var wts0 = cascadeData.worldToShadow[0];
            Shader.SetGlobalVectorArray(LianFrameData.WorldToShadowName, m_WorldToShadowRows);
            Shader.SetGlobalVector(LianFrameData.CascadeSphereRadiiSqName, cascadeData.sphereRadiiSq);
            Shader.SetGlobalVector(LianFrameData.CascadeClipDistancesName, cascadeData.clipDistances);
            Shader.SetGlobalVector(LianFrameData.CascadeCenter0Name, cascadeData.center0);
            Shader.SetGlobalVector(LianFrameData.CascadeCenter1Name, cascadeData.center1);
            Shader.SetGlobalVector(LianFrameData.CascadeCenter2Name, cascadeData.center2);
            Shader.SetGlobalVector(LianFrameData.ShadowMapTexelName,
                new Vector4(cascadeData.texelSize.x, cascadeData.texelSize.y,
                    cascadeData.shadowMapSize, cascadeData.shadowMapSize));
            Shader.SetGlobalFloatArray(LianFrameData.CascadeDitherName, LianFrameDataUtils.CascadeDither);

            if (hasSpecialShadow)
            {
                Matrix4x4 m = cascadeData.worldToShadow[3];
                m_SpecialWorldToShadowRows[0] = m.GetRow(0);
                m_SpecialWorldToShadowRows[1] = m.GetRow(1);
                m_SpecialWorldToShadowRows[2] = m.GetRow(2);
                m_SpecialWorldToShadowRows[3] = m.GetRow(3);
            }
            else
            {
                System.Array.Clear(m_SpecialWorldToShadowRows, 0, 4);
            }
            Shader.SetGlobalVectorArray(LianFrameData.SpecialWorldToShadowName, m_SpecialWorldToShadowRows);
        }

        protected override void Dispose(bool disposing)
        {
            ReleaseBuffers();
            m_DebugView = null;
        }
    }
}
