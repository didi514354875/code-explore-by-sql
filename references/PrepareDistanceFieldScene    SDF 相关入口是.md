 精确回答：它是渲染侧每帧的调度入口，但不是全流程的入口，而且它自己还有前置

 三个边界要同时成立才是准确说法：

 1. 唯一调用点只有两个——FDeferredShadingSceneRenderer::Render 和 FMobileSceneRenderer::Render（全库搜索 PrepareDistanceFieldScene
    只命中这两个 block）；
 2. 它前面有硬性前置：UpdateGlobalDistanceFieldViewOrigin 必须先跑（头文件把这条写成了契约）；
 3. 它是 scene 级、每渲染器每帧一次，不是 per-view（per-view 循环在它内部 SceneUpdateInputs.ForEachView）。

 ### 帧内顺序（两条渲染路径都有实证）

 ```cpp
// ① DeferredShadingRenderer.cpp（FDeferredShadingSceneRenderer::Render :1823-4400）
// :1946-1951
// 1. Update global distance field view origin
// This needs to be done prior to start Lumen scene lighting to ensure GlobalDistanceFieldData->CameraVelocityOffset is updated
if (SceneUpdateInputs) { UpdateGlobalDistanceFieldViewOrigin(*SceneUpdateInputs); }
if (RendererOutput == ERendererOutput::FinalSceneColor) { /* 2. Update lumen scene ... */ }
...
// :2010-2012
if (SceneUpdateInputs) { PrepareDistanceFieldScene(GraphBuilder, ExternalAccessQueue, *SceneUpdateInputs); }

// ② MobileShadingRenderer.cpp（FMobileSceneRenderer::Render :1182-1955）
if (EngineShowFlags.Lighting && !EngineShowFlags.VisualizeLightCulling && !Family.UseDebugViewPS()
    && (!View.bIsReflectionCapture || View.IsRuntimeReflectionCapture) && !View.bIsPlanarReflection)
{
    UpdateGlobalDistanceFieldViewOrigin(*SceneUpdateInputs);   // :1235
    PrepareDistanceFieldScene(GraphBuilder, ExternalAccessQueue, *SceneUpdateInputs);  // :1236
    break;                                                   // ← 每帧只调一次
}
 ```

 契约原文（ScenePrivate.h:998-1010）：

 ```cpp
/** Updates the global distance field view origin for all scene renderers.
 *  Must be called before PrepareDistanceFieldScene(...). */
extern void UpdateGlobalDistanceFieldViewOrigin(const FSceneRenderUpdateInputs&);
/** Prepares the distance field scene for all scene renderers.
 *  Must be called after UpdateGlobalDistanceFieldViewOrigin(...). */
extern void PrepareDistanceFieldScene(FRDGBuilder&, FRDGExternalAccessQueue&, const FSceneRenderUpdateInputs&);
 ```

 → 所以帧内最早的 SDF 相关入口是 UpdateGlobalDistanceFieldViewOrigin（GlobalDistanceField.cpp:799），PrepareDistanceFieldScene
 是它之后的第二环。

 ────────────────────────────────────────────────────────────────────────────────

 「入口」按层分成四个，只有一层归 PrepareDistanceFieldScene

 ┌─────────────────────────┬───────────────────────────────────────────┬────────────────────────┬─────────────────────────────────────┐
 │ 层                      │ 入口                                      │ 触发时机               │ 输入/输出                           │
 ├─────────────────────────┼───────────────────────────────────────────┼────────────────────────┼─────────────────────────────────────┤
 │ 数据（Engine）          │ FStaticMeshRenderData::Serialize /        │ 资产加载/cook          │ 产出                                │
 │                         │ FDistanceFieldVolumeData::CacheDerivedDat │                        │ FDistanceFieldVolumeData*（元数据 + │
 │                         │ a                                         │                        │ AlwaysLoadedMip）                   │
 ├─────────────────────────┼───────────────────────────────────────────┼────────────────────────┼─────────────────────────────────────┤
 │ 状态（Scene，事件驱动） │ FScene::AddPrimitiveSceneInfo_RenderThrea │ scene update           │ 填                                  │
 │                         │ d / FScene::Update /                      │ 阶段（可与渲染并行）   │ PendingAdd/Update/RemoveOperations  │
 │                         │ UpdatePrimitivesIsDrawn_RenderThread      │                        │ ，AssetStateArray 引用计数          │
 ├─────────────────────────┼───────────────────────────────────────────┼────────────────────────┼─────────────────────────────────────┤
 │ 帧调度（Renderer）      │ UpdateGlobalDistanceFieldViewOrigin →     │ 每帧 Render() 早期     │ drain 队列 + 上传 + 流式调度        │
 │                         │ PrepareDistanceFieldScene                 │                        │                                     │
 ├─────────────────────────┼───────────────────────────────────────────┼────────────────────────┼─────────────────────────────────────┤
 │ GPU 反馈（闭环）        │ GenerateStreamingRequests（被 Prepare     │ 帧末                   │ 产出下一帧要加载的 mip 列表         │
 │                         │ 内部调用）                                │                        │                                     │
 └─────────────────────────┴───────────────────────────────────────────┴────────────────────────┴─────────────────────────────────────┘

 也就是说：PrepareDistanceFieldScene 是「消费端」的统一入口，不是「生产端」的入口。 它一次消费上游三类输入——资产指针（来自 Engine 加载
 + Proxy::GetDistanceFieldAtlasData）、pending 队列（来自场景事件）、GPU 回读结果（来自上一帧的自己）——把它们收敛成 RDG 的 GPU 工作。

 它内部的第一步也不是 mesh SDF（进一步说明它是「调度点」）

 ```cpp
void PrepareDistanceFieldScene(...)         // DistanceFieldObjectManagement.cpp:977-1053
{
    const bool bShouldPrepareHeightFieldScene   = ShouldPrepareHeightFieldScene(SceneUpdateInputs);
    const bool bShouldPrepareDistanceFieldScene = ShouldPrepareDistanceFieldScene(SceneUpdateInputs);
    if (!bShouldPrepareDistanceFieldScene && !bShouldPrepareHeightFieldScene) { return; }

    ProcessPendingHeightFieldPrimitiveAddAndRemoveOps(Scene, IndicesToUpdateInHeightFieldObjectBuffers);   // ① height field
    if (bShouldPrepareHeightFieldScene) { GHFTextureAtlas.UpdateAllocations(...); UpdateGlobalHeightFieldObjectBuffers(...); }
    else if (HeightFieldObjectBuffers)  { delete ...; }                                                     // 不需要就回收缓冲

    if (bShouldPrepareDistanceFieldScene) {
        DistanceFieldSceneData.UpdateDistanceFieldObjectBuffers(...);   // ② mesh SDF 对象缓冲
        DistanceFieldSceneData.UpdateDistanceFieldAtlas(...);           // ③ mesh SDF 流式/上传
        SceneUpdateInputs.ForEachView([&](..., FViewInfo& View) {       // ④ 每视图
            if (ShouldPrepareGlobalDistanceField(Renderer)) { UpdateGlobalDistanceFieldVolume(...); }
            return true;
        });
    }
}
 ```

 注意 ④ 里还有一处条件释放：不需要 height field 时直接 delete HeightFieldObjectBuffers（缓冲生命周期也挂在这个入口上）。

 一句话

 PrepareDistanceFieldScene 是「每帧把 height field / mesh SDF / global SDF 三个子系统的 state 收敛并提交到
 RDG」的调度入口——在渲染侧叫它入口没问题；但在整个 SDF
 生命周期的视角下，它只是四个入口中「消费/提交」的那一个，前面还有引擎加载入口、场景事件入口。
