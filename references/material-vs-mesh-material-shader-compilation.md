# MaterialShaderType vs MeshMaterialShaderType Compilation Architecture

## Class Hierarchy

```
FShader
  └── FMaterialShader           ← DECLARE_SHADER_TYPE(Xxx, Material)
        └── FMeshMaterialShader ← DECLARE_SHADER_TYPE(Xxx, MeshMaterial)
```

- **FMaterialShader** (MaterialShader.h): Base class for shaders needing material parameters only.
  - `ShaderMetaType = FMaterialShaderType`
  - Holds: MaterialUniformBuffer, ParameterCollectionUniformBuffers, VTFeedbackBuffer
- **FMeshMaterialShader** (MeshMaterialShader.h): Base class for shaders needing material + VF parameters.
  - `ShaderMetaType = FMeshMaterialShaderType`
  - Inherits FMaterialShader, adds: `VertexFactoryParameters` (TMemoryImagePtr), `PassUniformBuffer`
  - Has `GetElementShaderBindings()` which binds vertex streams at runtime

## Compilation Key Difference: VF Dimension

**FShaderCompileJobKey construction:**
- MaterialShaderType: `FShaderCompileJobKey(this, nullptr, PermutationId)` — VF is null
- MeshMaterialShaderType: `FShaderCompileJobKey(this, VertexFactoryType, PermutationId)` — VF is explicit

This means MeshMaterialShader compilation produces **N variants per VF type** while MaterialShader produces exactly 1.

## Prepare Function Differences

### PrepareMaterialShaderCompileJob (MaterialShader.cpp L1836-1879)
1. Set SharedEnvironment from MaterialEnvironment
2. Material->SetupExtraCompilationSettings
3. ShaderType->SetupCompileEnvironment (no VF param)
4. `GlobalBeginCompileShader(..., nullptr, ShaderType, ...)` — VF = nullptr

### PrepareMeshMaterialShaderCompileJob (MeshMaterialShader.cpp L13-73)
1. Same SharedEnvironment and settings...
2. **★ VertexFactoryType->ModifyCompilationEnvironment()** — injects VF .ush includes + defines
3. ShaderType->SetupCompileEnvironment (includes VFType param)
4. `GlobalBeginCompileShader(..., VertexFactoryType, ShaderType, ...)` — VF passed

## VertexFactory::ModifyCompilationEnvironment (VertexFactory.h L455-475)

This is what VF injects into the compile environment for MeshMaterialShaders:

1. **Include remapping**: Maps `/Engine/Generated/VertexFactory.ush` → `#include "ActualVFFile.ush"`
   - Different VFs (FLocalVertexFactory, FGPUBaseSkinVertexFactory, FLandscapeVertexFactory, etc.) inject different headers
2. **Fwd include**: If VF has a forward declaration file, injects it and sets `USE_VERTEX_FACTORY_FWD`
3. **Define**: Sets `HAS_PRIMITIVE_UNIFORM_BUFFER = 1`
4. **Custom modifications**: Calls VF-specific `ModifyCompilationEnvironmentRef` function pointer (adds `GPUSKIN`, `MORPH_TARGET`, etc.)

Result: Same shader source code compiles to different binaries per VF due to different includes + defines.

## SubmitCompileJobs Loop Structure

In `FMaterialShaderMap::SubmitCompileJobs` (MaterialShader.cpp):

```
Phase 1: MeshMaterialShaderType (nested loop)
  for (MeshLayout : Layout.MeshShaderMaps)        ← iterate each VF
    for (Shader : MeshLayout.Shaders)              ← iterate each ShaderType
      ShaderType->BeginCompileShader(..., MeshLayout.VertexFactoryType, ...)
    for (Pipeline : MeshLayout.ShaderPipelines)
      FMeshMaterialShaderType::BeginCompileShaderPipeline(..., MeshLayout.VertexFactoryType, Pipeline, ...)
  → Products: Σ(ShaderTypes × VF Count)

Phase 2: MaterialShaderType (single loop)
  for (Shader : Layout.Shaders)                    ← no VF iteration
    ShaderType->BeginCompileShader(..., nullptr, ...)
  for (Pipeline : Layout.ShaderPipelines)
    FMaterialShaderType::BeginCompileShaderPipeline(..., Pipeline, ...)
  → Products: ShaderTypes count
```

## ShouldCompilePermutation Filter Chain

| Shader Category | Filter Layers |
|---|---|
| MaterialShader | ① Material::ShouldCache(ShaderType, nullptr) ② ShaderType::ShouldCompilePermutation |
| MeshMaterialShader | ① Material::ShouldCache(ShaderType, VFType) ② ShaderType::ShouldCompilePermutation(Params with VF) ③ VFType::ShouldCache(Params) |

## Why MaterialShaderType Doesn't Need VF

**Rendering purpose determines VF requirement:**

| | FMaterialShader | FMeshMaterialShader |
|---|---|---|
| Renders | Full-screen quads, volumes, light functions, decals | Scene meshes |
| Geometry source | Procedural (hardcoded verts / SV_VertexID) | VertexBuffer (parsed by VF) |
| VS input | Fixed transform, no vertex buffer read | VF-provided vertex streams (Position, Normal, UV, ...) |
| HLSL includes | No VertexFactory.ush | Includes VF-specific .ush |
| Examples | FDeferredDecalPS, FLightFunctionPS, FDebugViewModePS, FLightFunctionAtlasSlotPS | TBasePassVS/PS, TDepthOnlyVS, TShadowDepthVS, FHitProxyPS |

## Source File Locations

| Component | File |
|---|---|
| FMaterialShader class | Renderer/Public/MaterialShader.h |
| FMeshMaterialShader class | Renderer/Public/MeshMaterialShader.h |
| PrepareMaterialShaderCompileJob | Engine/Private/Materials/MaterialShader.cpp L1836 |
| PrepareMeshMaterialShaderCompileJob | Engine/Private/Materials/MeshMaterialShader.cpp L13 |
| FMaterialShaderType::BeginCompileShader | MaterialShader.cpp L1885 |
| FMeshMaterialShaderType::BeginCompileShader | MeshMaterialShader.cpp L82 |
| SubmitCompileJobs (dual loop) | MaterialShader.cpp L2509-2725 |
| VF::ModifyCompilationEnvironment | RenderCore/Public/VertexFactory.h L455 |
| GlobalBeginCompileShader | Engine/Private/ShaderCompiler/ShaderCompiler.cpp L3149 |
