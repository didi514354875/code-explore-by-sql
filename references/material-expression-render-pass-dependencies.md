# MaterialExpression → Render Pass Dependencies

## Overview

UE material expressions that go beyond PBR inputs (BaseColor/Metallic/Roughness/Normal) declare dependencies via `FMaterialCompilationOutput` flags during `Compile()`. The renderer reads these flags at frame time to activate passes, bind UniformBuffers, and inject shader defines. This is a **declarative dependency** system: nodes declare needs, renderer dispatches.

## Key Source Files

- `Engine/Source/Runtime/Engine/Public/MaterialShared.h` — `FMaterialCompilationOutput` flags
- `Engine/Source/Runtime/Engine/Private/Materials/HLSLMaterialTranslator.cpp` — Compile() implementations, flag setting, HLSL code generation
- `Engine/Source/Runtime/Engine/Public/Materials/MaterialExpressionCustomOutput.h` — Base class for custom output expressions
- `Engine/Source/Runtime/Engine/Public/MaterialSceneTextureId.h` — `ESceneTextureId` enum (31+ scene texture types)
- `Engine/Shaders/Private/MaterialTemplate.ush` — Shader-side code injection points
- `Engine/Source/Runtime/Renderer/Private/DeferredShadingRenderer.cpp` — Pass dispatch driven by material flags

## Compilation Output Flags → Pass Mapping

| Flag | Set By | Drives |
|------|--------|--------|
| `bNeedsSceneTextures` | SceneTexture, SceneColor, SceneDepth nodes | `NEEDS_SCENE_TEXTURES` define, SceneTexturesUB binding |
| `bUsesWorldPositionOffset` | WPO input pin | DepthPrepass + Shadow WPO + Velocity dual-frame |
| `bUsesDisplacement` | Tessellation Multiplier pin | Hull/Domain shader stages |
| `bModifiesMeshPosition` | WPO || PixelDepthOffset || Displacement | Blocks Nanite fast path |
| `bUsesPixelDepthOffset` | PixelDepthOffset pin | Depth write modification in base pass |
| `bUsesGlobalDistanceField` | DistanceFieldApproxAO, DistanceFieldGradient, DistanceToNearestSurface | SDF Volume binding |
| `bUsesEyeAdaptation` | EyeAdaptation, EyeAdaptationInverse | Exposure texture binding |
| `bUsesDBufferTextureLookup` | DBufferTexture node | DBuffer pre-pass execution |
| `bUsesPerInstanceCustomData` | PerInstanceCustomData | GPU Scene data layout |
| `bUsesAnisotropy` | Anisotropy input pin | GBuffer anisotropy channel |
| `bUsesMotionVectorWorldOffset` | MotionVectorWorldOffsetOutput | Velocity Pass offset |
| `bUsesDistanceCullFade` | DistanceCullFade | Per-instance fade in GPU Scene |

## 1. Scene Texture Access Nodes

**Nodes**: `SceneTexture`, `SceneColor`, `SceneDepth`, `SceneDepthWithoutWater`, `UserSceneTexture`, `SceneTexelSize`

**Compile flow**:
```
UMaterialExpressionSceneTexture::Compile()
  → Compiler->SceneTextureLookup(UV, SceneTextureId, bFiltered)
    → FHLSLMaterialTranslator::SceneTextureLookup()
      → UseSceneTextureId(SceneTextureId, true)
        → bNeedsSceneTextures = true
        → SetIsSceneTextureUsed(SceneTextureId)
      → AddCodeChunk("SceneTextureLookup(%s, %s, %s)")
```

**Shader define**: `#define NEEDS_SCENE_TEXTURES 1`

**HLSL generation** (HLSLMaterialTranslator.cpp:8520-8607):
```hlsl
// Auto-generated sampling code
SceneTextureLookup(GetDefaultSceneTextureUV(Parameters, PPI_SceneDepth), PPI_SceneDepth, false)
// Or with custom UV:
SceneTextureLookup(ViewportUVToSceneTextureUV(customUV, PPI_SceneDepth), PPI_SceneDepth)
```

**ESceneTextureId enum** (31+ types): PPI_SceneColor, PPI_SceneDepth, PPI_CustomDepth, PPI_CustomStencil, PPI_BaseColor, PPI_Specular, PPI_Metallic, PPI_WorldNormal, PPI_Roughness, PPI_MaterialAO, PPI_AmbientOcclusion, PPI_Velocity, PPI_ShadingModelColor, PPI_ShadingModelID, PPI_DiffuseColor, PPI_SpecularColor, PPI_SubsurfaceColor, PPI_WorldTangent, PPI_Anisotropy, PPI_IsFirstPerson, PPI_PostProcessInput0~6, PPI_UserSceneTexture0~6.

**Restrictions enforced at compile time**: Decals can only access SceneDepth/CustomDepth/CustomStencil/WorldNormal. SingleLayerWater can only access CustomDepth/CustomStencil. PostProcess materials should use PostProcessInput0 instead of SceneColor.

## 2. World Position Offset / Displacement — Multi-Pass联动

**Nodes**: WPO input pin, WorldPosition, Tessellation Multiplier input

**Compile flow** (HLSLMaterialTranslator.cpp):
```cpp
MaterialCompilationOutput.bUsesWorldPositionOffset = bUsesWorldPositionOffset;
MaterialCompilationOutput.bUsesDisplacement = bUsesDisplacement;
MaterialCompilationOutput.bModifiesMeshPosition = bUsesPixelDepthOffset || bUsesWorldPositionOffset || bUsesDisplacement;
```

**Affected passes**:
- **Depth Prepass**: WPO materials must go through depth pre-pass (final position determined in VS)
- **Base Pass**: VS calls `GetMaterialWorldPositionOffset()`
- **Shadow Pass**: Must also execute WPO for shadow一致性
- **Velocity Pass**: Needs both current + previous frame WPO values
- **Nanite**: `RasterPipeline.bWPOEnabled` flag, affects pipeline selection

**Shader code generation** (MaterialTemplate.ush):
```hlsl
float3 GetMaterialWorldPositionOffsetRaw(FMaterialVertexParameters Parameters) {
    %{get_material_world_position_offset_raw}; // user graph code injected here
}
float3 GetMaterialWorldPositionOffset(FMaterialVertexParameters Parameters) {
    if (ShouldEnableWorldPositionOffset(Parameters))
        return ClampWorldPositionOffset(Parameters, GetMaterialWorldPositionOffsetRaw(Parameters));
    return float3(0,0,0);
}
// Same pattern for GetMaterialPreviousWorldPositionOffset (velocity pass)
```

## 3. CustomOutput Node Family — Independent Render Pipelines

Base class: `UMaterialExpressionCustomOutput` (MaterialExpressionCustomOutput.h)

**Compile mechanism** (HLSLMaterialTranslator.cpp:984-1047):
```cpp
// For each CustomOutput node:
// 1. Generate #define NUM_MATERIAL_OUTPUTS_<NAME> <count>
// 2. Compile per-output-index at specified ShaderFrequency (VS/PS/CS)
// 3. Previous frame evaluation if NeedsPreviousFrameEvaluation()
```

### Registered CustomOutput Subclasses

| Node | GetFunctionName() | ShaderFreq | Render Pipeline |
|------|-------------------|------------|-----------------|
| RuntimeVirtualTextureOutput | `GetVirtualTextureOutput0~7` | PS | Virtual Texture render pass |
| LandscapeGrassOutput | custom | PS | Grass instance generation |
| ThinTranslucentMaterialOutput | custom | PS | Separate Translucency pass |
| SingleLayerWaterMaterialOutput | custom | PS | SLW composite pass |
| VolumetricAdvancedMaterialOutput | custom | PS | Volumetric fog pass |
| NeuralPostProcessNode | custom | PS | Neural rendering pass |
| MaterialCache | custom | PS | Material cache system |
| BentNormalCustomOutput | custom | PS | GBuffer bent normal extension |
| ClearCoatNormalCustomOutput | custom | PS | GBuffer clear coat bottom normal |
| MotionVectorWorldOffsetOutput | custom | VS | Velocity pass offset |
| FirstPersonOutput | custom | PS | First-person rendering isolation |
| TemporalResponsivenessOutput | custom | PS | TAA integration weights |
| TangentOutput | custom | VS | Custom tangent output |
| SubsurfaceMediumMaterialOutput | custom | PS | Medium scattering pass |
| AbsorptionMediumMaterialOutput | custom | PS | Medium absorption pass |
| LandscapePhysicalMaterialOutput | custom | PS | Physical material mapping |
| PhysicalMaterialOutput (RenderTrace plugin) | custom | PS | Physical material output |

**Virtual Texture example** (VirtualTextureMaterial.usf):
```hlsl
// Generated function calls in VT render pass
half3 BaseColor = GetVirtualTextureOutput0(MaterialParameters);
half Specular = GetVirtualTextureOutput1(MaterialParameters);
half Roughness = GetVirtualTextureOutput2(MaterialParameters);
half3 Normal = GetVirtualTextureOutput3(MaterialParameters);
```

## 4. Shading Model → Pass Activation

| Shading Model | Extra Pass(es) | Key Material Inputs |
|---|---|---|
| SubsurfaceProfile | `AddSubsurfacePass()` (separable SSS) | SubsurfaceColor input |
| Subsurface | `AddSubsurfacePass()` (wrap mode) | SubsurfaceColor + Opacity |
| Hair | `RenderHairStrandsSceneColorScattering()` + hair shadows | HairAttributes, HairColor |
| Eye | Corneal refraction SSS + pupil rendering | Eye-specific parameters |
| ClearCoat | GBuffer bottom normal via ClearCoatNormalCustomOutput | ClearCoat + Bottom Normal |
| SingleLayerWater | SLW composite + water scattering | SingleLayerWaterMaterialOutput |
| ThinTranslucent | Independent translucency pass | ThinTranslucentMaterialOutput |

**Subsurface pass insertion point** (DeferredShadingRenderer.cpp):
```cpp
// After lighting, before post-processing
AddSubsurfacePass(GraphBuilder, SceneTextures, Views);
Substrate::AddSubstrateOpaqueRoughRefractionPasses(GraphBuilder, SceneTextures, Views);
RenderHairStrandsSceneColorScattering(GraphBuilder, SceneTextures.Color.Target, Scene, Views);
```

## 5. Other Dependency Categories

- **DBuffer Decals**: `bUsesDBufferTextureLookup` → DBuffer pre-pass renders decal Albedo/Normal/Specular/Opacity
- **Distance Field**: `bUsesGlobalDistanceField` → Global SDF Volume data via GPUScene
- **Eye Adaptation**: `bUsesEyeAdaptation` → Auto-exposure texture from FEyeAdaptationManager
- **Per-Instance Data**: `bUsesPerInstanceCustomData` → GPU Scene Buffer SRV via PrimitiveId
- **Path Tracing**: PathTracingQualitySwitch, PathTracingRayTypeSwitch, PathTracingBufferTexture → Ray Tracing pass
- **Velocity**: MotionVectorWorldOffsetOutput → custom motion offset in Velocity Pass VS

## Design Pattern Summary

```
MaterialExpression Node
    ↓ Compile()
FHLSLMaterialTranslator
    ↓ Sets FMaterialCompilationOutput flags + generates HLSL
┌──────────────────────────────────────┐
│ Compilation output flags + defines    │
│ → read by FMaterialShaderMap         │
│ → read by FScene / FRenderer         │
└──────────────────────────────────────┘
    ↓
Renderer activates passes, binds UBs, sets shader defines
```

The declarative pattern means: **nodes never call into the renderer directly**. They set flags during offline compilation, and the renderer reads those flags at runtime. This separates the material authoring concern from the rendering pipeline concern.
