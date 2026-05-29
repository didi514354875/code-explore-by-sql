# UE Material ShaderMap Architecture

ShaderMap creation, compilation data management, and FMaterial↔ShaderMap lifecycle.

## Core Class Hierarchy

```
FShaderMapBase
 └── TShaderMap<FMaterialShaderMapContent, FShaderMapPointerTable>
      └── FMaterialShaderMap (+ FDeferredCleanupInterface)

FMaterialShaderMapContent : FShaderMapContent
 ├── OrderedMeshShaderMaps[] → FMeshMaterialShaderMap (per VertexFactory)
 ├── MaterialCompilationOutput (FUniformExpressionSet + capability flags)
 └── ShaderProcessedSource[] (Editor only)

FMeshMaterialShaderMap : FShaderMapContent
 └── VertexFactoryTypeName → actual FShader instances (inherited from FShaderMapContent)
```

## FMaterial's Dual ShaderMap References

```cpp
// MaterialShared.h L2057 class FMaterial
TRefCountPtr<FMaterialShaderMap> GameThreadShaderMap;       // GT owns
TRefCountPtr<FMaterialShaderMap> RenderingThreadShaderMap;  // RT owns
uint32 GameThreadCompilingShaderMapId;     // async compile tracking (GT)
uint32 RenderingThreadCompilingShaderMapId; // async compile tracking (RT)
std::atomic<bool> bGameThreadShaderMapIsComplete;
std::atomic<bool> bRenderingThreadShaderMapIsComplete;
```

- GT and RT hold independent ref-counted ShaderMap pointers.
- Synchronized via `ENQUEUE_RENDER_COMMAND` — GT sets first, RT receives asynchronously.
- `GetRenderingThreadShaderMap()` (L1379): `check(IsInParallelRenderingThread()); return RenderingThreadShaderMap;`

## ShaderMap Creation Pipeline (5 Phases)

### Phase 1: CacheShaders Entry Point
**File**: `MaterialShared.cpp L2837`

```
FMaterial::CacheShaders(ShaderMapId, PrecompileMode)
 ├─ inline shaders? → FindId() in GIdToMaterialShaderMap → reuse or Register()
 ├─ Editor path:
 │   → FindId() hit + compiling? → SetCompilingShaderMap() + GetFinalizedClone()
 │   → DDC has it? → BeginLoadFromDerivedDataCache() async
 │   → nothing? → BeginCompileShaderMap()
 └─ Cooked path: inline ShaderMap or fatal
```

### Phase 2: BeginCompileShaderMap
**File**: `MaterialShared.cpp L3546`

1. `new FMaterialShaderMap()` — create empty map
2. `Translate()` → generates HLSL + `FMaterialCompilationOutput` + `FSharedShaderCompilerEnvironment`
3. `CreateBufferStruct()` from `UniformExpressionSet` → `SetupMaterialEnvironment()`
4. `NewShaderMap->Compile(this, ShaderMapId, Environment, Output, Platform, PrecompileMode)`
5. Result handling:
   - **Synchronous**: `FinalizeContent()` + `SetGameThreadShaderMap(NewShaderMap)` immediately
   - **Async**: `SetGameThreadShaderMap(NewShaderMap->AcquireFinalizedClone())` — render uses clone while compilation continues

### Phase 3: FMaterialShaderMap::Compile
**File**: `MaterialShader.cpp L2733`

1. `AcquireCompilingId(MaterialEnvironment)` — unique compile session ID
2. Create `FMaterialShaderMapContent`, store `MaterialCompilationOutput`
3. `Material->SetCompilingShaderMap(this)` — bidirectional link
4. `Register(Platform)` — insert into `GIdToMaterialShaderMap`
5. `bCompilationFinalized = false`, `bCompiledSuccessfully = false`
6. `SubmitCompileJobs(CompilingId, ...)` → dispatch to `GShaderCompilingManager`
   - Returns 0? → mark finalized + save to DDC immediately
7. Synchronous mode: `GShaderCompilingManager->FinishCompilation()`

### Phase 4: SubmitCompileJobs
**File**: `MaterialShader.cpp L2474`

1. `AcquireMaterialShaderMapLayout(Platform, Flags, MaterialParameters)` — determines VF + ShaderType matrix
2. For each `FMeshMaterialShaderMapLayout` in Layout:
   - For each ShaderType: skip already-compiled, call `ShaderType->BeginCompileShader(..., CompileJobs)`
   - For each ShaderPipeline: create pipeline-level compile jobs
3. Submit all jobs to `GShaderCompilingManager`

### Phase 5: ProcessCompiledShaderMaps (async completion)
**File**: `ShaderCompiler.cpp L2026`

1. Group finished jobs by `CompilingId`
2. `CheckSingleJob()` — verify each job succeeded
3. Success → `CompilingShaderMap->ProcessCompilationResults()`:
   - Per job: `ProcessCompilationResultsForSingleJob()` → create `FShader` instance
   - Place into correct `FMeshMaterialShaderMap` based on VFType
   - Assemble `FShaderPipeline` from stage jobs
4. `AcquireFinalizedClone()` → snapshot for rendering
5. `MaterialsToUpdate.Add(Material, ShaderMapToUseForRendering)`
6. All materials complete → `bCompilationFinalized = true`, `SaveToDerivedDataCache()`, `ReleaseCompilingId()`
7. `FMaterial::SetShaderMapsOnMaterialResources(MaterialsToUpdate)` — batch update GT+RT

## SetShaderMapsOnMaterialResources — GT/RT Dual Update
**File**: `MaterialShared.cpp L5568`

```
GT loop: Material->GameThreadShaderMap = ShaderMap (direct)
         bGameThreadShaderMapIsComplete = IsComplete()

ENQUEUE_RENDER_COMMAND:
  RT loop: Material->SetRenderingThreadShaderMap(ShaderMap)
           bRenderingThreadShaderMapIsComplete = IsComplete()
  Editor: refresh all FMaterialRenderProxy uniform expression caches
```

- Waits for async RDG tasks first: `FRDGBuilder::WaitForAsyncExecuteTask()`
- Iterates all `FMaterialRenderProxy` instances to recache uniform expressions

## Global Deduplication Cache

```cpp
// MaterialShader.cpp — static members of FMaterialShaderMap
static TMap<FMaterialShaderMapId, FMaterialShaderMap*> GIdToMaterialShaderMap[SP_NumPlatforms];
static FCriticalSection GIdToMaterialShaderMapCS;
```

- `FindId(ShaderMapId, Platform)`: lock → `FindRef` → return (L1998)
- `Register(Platform)`: lock → `Add(ShaderMapId, this)` if not already present (L3654)
- Same `FMaterialShaderMapId` → single ShaderMap instance shared across all Materials

## FMaterialShaderMapId — Unique Key
**File**: `MaterialShared.h L1193`

| Field | Purpose |
|-------|---------|
| `CookedShaderMapIdHash` | FSHAHash for cooked lookups |
| `BaseMaterialId` (FGuid) | Editor: changes on any material edit |
| `QualityLevel` | EMaterialQualityLevel |
| `FeatureLevel` | ERHIFeatureLevel |
| `Usage` | EMaterialShaderMapUsage (Default/Lightmass/Export) |
| `StaticSwitchParameters[]` | Static switch values |
| `StaticComponentMaskParameters[]` | Static mask values |
| `ShaderTypeDependencies[]` | Which shader types are included |
| `VertexFactoryTypeDependencies[]` | Which VF types are included |
| `TextureReferencesHash` | Hash of referenced textures |
| `BasePropertyOverridesHash` | Material instance overrides |
| `LayoutParams` | Platform type layout params |

## Key Source Files

| File | Content |
|------|---------|
| `Engine/Public/MaterialShared.h` | FMaterial, FMaterialShaderMap, FMaterialShaderMapId, FMaterialShaderMapContent |
| `Engine/Private/Materials/MaterialShared.cpp` | CacheShaders, BeginCompileShaderMap, SetGameThreadShaderMap, SetShaderMapsOnMaterialResources |
| `Engine/Private/Materials/MaterialShader.cpp` | FMaterialShaderMap::Compile, SubmitCompileJobs, ProcessCompilationResults, Register, FindId |
| `Engine/Private/ShaderCompiler/ShaderCompiler.cpp` | FShaderCompilingManager::ProcessCompiledShaderMaps |
| `Engine/Private/Materials/MaterialRenderProxy.cpp` | GetRenderingThreadShaderMap callers, SubmitCompileJobs_RenderThread |

## Runtime Lookup Pattern

```cpp
// Standard rendering code:
const FMaterialShaderMap* ShaderMap = Material.GetRenderingThreadShaderMap();
// → check(IsInParallelRenderingThread()); return RenderingThreadShaderMap;

TShaderRef<FBasePassVS> VS = ShaderMap->GetShader<FBasePassVS>(VertexFactoryType, PermId);
// → GetMeshShaderMap(VFType)->GetShader(ShaderType, PermId)
```

## Design Summary

| Mechanism | Implementation |
|-----------|---------------|
| GT/RT double buffering | Two independent TRefCountPtr, synced via ENQUEUE_RENDER_COMMAND |
| Global dedup | GIdToMaterialShaderMap[Platform] keyed by FMaterialShaderMapId |
| DDC persistence | SaveToDerivedDataCache after compile, BeginLoadFromDerivedDataCache on cache |
| Clone for async | AcquireFinalizedClone() — render uses snapshot, compilation continues on original |
| CompilingId tracking | Global uint32 per compile session, Material links via (GT/RT)CompilingShaderMapId |
| Shared compilation | CompilingMaterialDependencies[] — one ShaderMap serves multiple Materials |
| Deferred cleanup | FDeferredCleanupInterface — ref-count reaches 0 → defer deletion until RT safe |
