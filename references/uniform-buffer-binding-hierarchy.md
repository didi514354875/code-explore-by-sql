# UE Uniform Buffer Binding Hierarchy

Four-layer UB system for mesh drawing, from broadest to narrowest scope:

## Layer Overview

| Layer | Struct | Scope | Defined In | Created |
|-------|--------|-------|-----------|---------|
| Scene | FSceneUniformParameters | All Views, whole scene | SceneUniformBuffer.h (runtime composition) | Per-frame, lazy via GetBuffer() |
| View | FViewUniformShaderParameters | Per View/camera | SceneView.h (X-Macro + GLOBAL_SHADER_PARAMETER_STRUCT) | Per-frame per-View, InitRHIResources |
| Light | FForwardLightUniformParameters | Per View | SceneRendering.h (GLOBAL_SHADER_PARAMETER_STRUCT) | Per-frame per-View, PrepareForwardLightData |
| Primitive | via GPU Scene Buffer | Per Mesh | GPUScene PrimitiveDataBuffer | Persistent, GPU Scene Update |
| Material | Per-material instance | Per draw call | Material shader compilation | Per-material, cached |

## 1. View Uniform Buffer — FViewUniformShaderParameters

### Definition Pattern: X-Macro Table

```cpp
// SceneView.h line ~849
#define VIEW_UNIFORM_BUFFER_MEMBER_TABLE \
    VIEW_UNIFORM_BUFFER_MEMBER_PER_VIEW(FMatrix44f, TranslatedWorldToClip) \
    VIEW_UNIFORM_BUFFER_MEMBER_PER_VIEW(FMatrix44f, ViewToClip) \
    VIEW_UNIFORM_BUFFER_MEMBER(FVector3f, ViewOriginHigh) \
    VIEW_UNIFORM_BUFFER_MEMBER(FVector3f, ViewForward) \
    // ... 120+ members (matrices, camera params, FOV, TAA jitter, time...)

BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT_WITH_CONSTRUCTOR(FViewUniformShaderParameters, ENGINE_API)
    VIEW_UNIFORM_BUFFER_MEMBER_TABLE   // expands to SHADER_PARAMETER macros
    // + ~50 texture/sampler resources (atmosphere LUTs, DF textures, lightmap...)
    SHADER_PARAMETER_TEXTURE(Texture2D, AtmosphereTransmittanceTexture)
    SHADER_PARAMETER_TEXTURE(Texture3D, GlobalDistanceFieldPageAtlasTexture)
END_GLOBAL_SHADER_PARAMETER_STRUCT()
```

**Why X-Macro:** Members reused in 3 places:
- `BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT` → struct + reflection generation
- `CopyViewParametersOnly()` → Instanced Stereo selective copy
- `PER_VIEW` vs non-PER_VIEW distinction (which fields differ per eye vs shared)

### Creation Flow

```
FSceneRenderer::Render()
  → InitViews()
    → FViewInfo::InitRHIResources()
      → SetupUniformBufferParameters()      // fill ViewParams struct
      → CreateViewUniformBuffers()           // TUniformBufferRef::CreateUniformBufferImmediate
        → ViewUniformBuffer = created
        → InstancedViewUniformBuffer = created (for stereo)
```

### Binding to Shader

```cpp
// ShaderBaseClasses.cpp
void FMaterialShader::SetViewParameters(BatchedParameters, View, ViewUniformBuffer)
{
    SetUniformBufferParameter(BatchedParameters, ViewUniformBufferParameter, ViewUniformBuffer);
    // + InstancedView UB if stereo
}
```

HLSL: Static slot registered via `IMPLEMENT_GLOBAL_SHADER_PARAMETER_STRUCT`. Auto-generated cbuffer with `View.ViewToClip`, `View.TranslatedWorldToClip`, etc.

## 2. Forward Light Uniform Buffer — FForwardLightUniformParameters

### Definition

```cpp
// SceneRendering.h line ~651
BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT_WITH_CONSTRUCTOR(FForwardLightUniformParameters, )
    SHADER_PARAMETER(FVector3f, DirectionalLightDirection)
    SHADER_PARAMETER(FVector3f, DirectionalLightColor)
    SHADER_PARAMETER_ARRAY(FMatrix44f, DirectionalLightTranslatedWorldToShadowMatrix, [4])
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, DirectionalLightShadowmapAtlas)
    SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<float4>, ForwardLightBuffer)
    SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<uint>, NumCulledLightsGrid)
    SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<uint>, CulledLightDataGrid32Bit)
    // ...
END_GLOBAL_SHADER_PARAMETER_STRUCT()
```

HLSL binding name: `"ForwardLightStruct"` (via `IMPLEMENT_GLOBAL_SHADER_PARAMETER_STRUCT`)

### Creation & Fill

```
DeferredShadingRenderer::Render()
  → PrepareForwardLightData()
    → ComputeLightGrid (LightGridInjectionCS)
      → ForwardLightParams.DirectionalLightDirection = ...
      → ForwardLightParams.DirectionalLightColor = ...
      → LightGridInjectionCS generates CulledLightDataGrid
    → ForwardLightUniformBuffer = GraphBuilder.CreateUniformBuffer(...)
    → View.ForwardLightingResources.SetUniformBuffer(ForwardLightUniformBuffer)
```

### Binding Pattern

Forward path: embedded in `FSharedBasePassUniformParameters`:
```cpp
BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT(FSharedBasePassUniformParameters,)
    SHADER_PARAMETER_STRUCT(FForwardLightUniformParameters, Forward)
    SHADER_PARAMETER_STRUCT(FReflectionUniformParameters, Reflection)
    SHADER_PARAMETER_STRUCT(FSceneTextureUniformParameters, SceneTextures)
END_GLOBAL_SHADER_PARAMETER_STRUCT()
```

Deferred path: bound via `SHADER_PARAMETER_RDG_UNIFORM_BUFFER(FForwardLightUniformParameters, ForwardLightStruct)` per-pass.

## 3. Scene Uniform Buffer — FSceneUniformParameters

Covered in `references/scene-uniform-buffer-architecture.md`. Key points:
- Self-registration via `IMPLEMENT_SCENE_UB_STRUCT`
- Runtime layout composition via `FShaderParametersMetadataBuilder`
- Dirty tracking + lazy RDG buffer creation
- HLSL access: `Scene.GPUScene.xxx`, `Scene.NaniteMaterials.xxx`, etc.

## 4. Primitive Data — GPU Scene Buffer

Not a traditional UB. Accessed via:
```hlsl
// SceneData.ush
Scene.GPUScene.GPUScenePrimitiveSceneData[PrimitiveId * STRIDE + offset]
```

Persistent structured buffer, updated by `FGPUScene::Update()`. Fetched in vertex shader via `GetPrimitiveData(PrimitiveId)`.

## Complete Draw Mesh Binding Flow

```
FDeferredShadingRenderer::Render()
│
├── InitViews()
│   ├── Per View: InitRHIResources() → CreateViewUniformBuffers()
│   ├── GPUScene.FillSceneUniformBuffer() → SceneUB.Set(GPUScene, ...)
│   ├── Extensions.UpdateSceneUniformBuffer() → SceneUB.Set(Nanite, HairStrands, ...)
│   └── PrepareForwardLightData() → View.ForwardLightingResources = UB
│
├── RenderBasePass() / any Mesh Pass
│   ├── Per Visible Mesh: FMeshBatch → FMeshDrawCommand
│   │
│   ├── At submit time, bind all UBs:
│   │   ① View UB: FMaterialShader::SetViewParameters(View.ViewUniformBuffer)
│   │   ② Scene UB: GetSceneUniforms().GetBuffer(GraphBuilder) → static slot
│   │   ③ Forward Light: SharedBasePassParams.Forward = View's ForwardLightUB
│   │   ④ Material: FMaterialShader::SetParameters(MaterialProxy, Material, View)
│   │   ⑤ Primitive: Scene.GPUScene.GPUScenePrimitiveSceneData[id] (SRV)
│   │
│   └── RHICmdList.DrawIndexedPrimitive()
```

## Key Design Decisions

| Aspect | Scene UB | View UB | Light UB | Primitive |
|--------|----------|---------|----------|-----------|
| Layout | Runtime dynamic (self-registration) | Compile-time fixed (X-Macro) | Compile-time fixed | GPU Buffer, fixed stride |
| Extensibility | Plugins can add members | Not needed (camera params fixed) | Fixed struct, dynamic buffer count | Fixed layout, dynamic instance count |
| Update freq | Per-frame once (dirty tracking) | Per-frame per-View | Per-frame per-View | Continuous GPU Scene update |
| RDG integration | GetBuffer() → TRDGUniformBufferRef | CreateUniformBufferImmediate | GraphBuilder.CreateUniformBuffer | GraphBuilder.CreateSRV |
| HLSL access | Scene.GPUScene.xxx | View.ViewToClip | Forward.DirectionalLightColor | GetPrimitiveData(id) |

**Philosophy:** Fixed structures use GLOBAL_SHADER_PARAMETER_STRUCT + static slots. Extensible structures use self-registration + runtime composition.
