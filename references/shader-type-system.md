# UE Shader Type System: Definition, Collection, Compilation Decision

Source files analyzed: Shader.h/Shader.cpp, VertexFactory.h/VertexFactory.cpp, MaterialShaderType.h, MeshMaterialShaderType.h, MaterialShader.cpp, MaterialShared.cpp, GlobalShader.cpp.

## 1. Three Meta-Types

| Type | Purpose | Key Fields | Sorted Array |
|------|---------|-----------|--------------|
| FShaderType | Describes a shader class (VS/PS/CS/etc.) | Name, SourceFilename, FunctionName, Frequency, TotalPermutationCount, ShouldCompilePermutationRef (fn ptr) | `GetSortedTypes(EShaderTypeForDynamicCast)` |
| FVertexFactoryType | Describes vertex data layout | Name, ShaderFilename, Flags (UsedWithMaterials, SupportsRayTracing...), ShouldCacheRef (fn ptr) | `GetSortedMaterialTypes()` |
| FShaderPipelineType | Groups FShaderType stages into a pipeline | Name, AllStages[SF_NumFrequencies], Stages[], bShouldOptimizeUnusedOutputs | `GetSortedTypes(CastType)` |

All three use identical triple-index: **GlobalLinkedList** (`GetTypeList()`) + **HashMap** (`GetNameToTypeMap()`) + **SortedArray**.

## 2. Definition Macros

### FShaderType
```
DECLARE_SHADER_TYPE(ShaderClass, ShaderMetaTypeShortcut)
  → declares GetStaticType(), ShaderTypeRegistration, vtable stubs

IMPLEMENT_SHADER_TYPE(TemplatePrefix, ShaderClass, SourceFilename, FunctionName, Frequency)
  → static ShaderMetaType StaticType{...}; // constructs & registers
  → static FShaderTypeRegistration{GetStaticType}; // deferred trigger
```

Subtypes: FGlobalShaderType, FMaterialShaderType, FMeshMaterialShaderType.
Each has its own IMPLEMENT macro (IMPLEMENT_GLOBAL_SHADER_TYPE, IMPLEMENT_MATERIAL_SHADER_TYPE, etc.)

### FVertexFactoryType
```
DECLARE_VERTEX_FACTORY_TYPE(FactoryClass)
  → declares static FVertexFactoryType StaticType

IMPLEMENT_VERTEX_FACTORY_TYPE(FactoryClass, ShaderFilename, Flags)
  → constructs StaticType directly (no deferred registration)
```

### FShaderPipelineType
```
IMPLEMENT_SHADERPIPELINE_TYPE_VSPS(PipelineName, VSType, PSType, bRemoveUnused)
  → static FShaderPipelineType with stage pointers from VSType::GetStaticType()
```

Variants: VSPS, VS, VSGSPS, VSGS, MSPS, MSASPS.

## 3. Registration Timeline

```
Module loading (ELoadingPhase::PostConfigInit)
  → IMPLEMENT_SHADER_TYPE triggers FShaderTypeRegistration constructor
    → GetInstances().Add(this)  // only enqueues, no FShaderType yet

LaunchEngineLoop
  → FShaderTypeRegistration::CommitAll()
    → for each registration: LazyShaderTypeAccessor()  // triggers GetStaticType()
      → FShaderType constructor:
        GlobalListLink.LinkHead(GetTypeList())
        GetNameToTypeMap().Add(HashedName, this)
        SortedTypes.Insert(this, sortedIndex)
    → bShaderTypesInitialized = true

Note: FVertexFactoryType and FShaderPipelineType register directly in constructor (no deferred mechanism).
```

## 4. Three-Tier Compilation Decision

### Tier 1: Material->ShouldCache(ShaderType, VFType)
Checks material usage flags against ShaderType requirements.

### Tier 2: VF->ShouldCache (VertexFactory level)
```
FMeshMaterialShaderType::ShouldCompileVertexFactoryPermutation(Platform, MaterialParams, VFType, ShaderType, Flags)
  → calls VFType->ShouldCache(Parameters)
    → calls (*ShouldCacheRef)(Parameters)  // VF's ShouldCompilePermutation
```

### Tier 3: ShaderType->ShouldCompilePermutation
```
FShaderType::ShouldCompilePermutation(Parameters)
  → ShouldCompileShaderFrequency(Frequency, Platform)  // platform freq check
  && (*ShouldCompilePermutationRef)(Parameters)          // user's static function
```

Pipeline variant checks ALL stages:
```
FMaterialShaderType::ShouldCompilePipeline(Pipeline, Platform, ...)
  → for each stage in Pipeline->GetStages():
      if (!ShaderType->ShouldCompilePermutation(Parameters))
          return false;
  return true;  // all stages must pass
```

## 5. Collection in AcquireMaterialShaderMapLayout

Source: MaterialShader.cpp L3162 `CreateLayout()`.

```
SortedMaterialShaderTypes = FShaderType::GetSortedTypes(Material);
SortedMeshMaterialShaderTypes = FShaderType::GetSortedTypes(MeshMaterial);
SortedMaterialPipelineTypes = FShaderPipelineType::GetSortedTypes(Material);
SortedMeshMaterialPipelineTypes = FShaderPipelineType::GetSortedTypes(MeshMaterial);

// Phase 1: Material shaders (no VF dependency)
for each ShaderType in SortedMaterialShaderTypes:
  for each PermutationId:
    if ShouldCompilePermutation(Platform, MaterialParams, PermId, Flags):
      Layout.Shaders.Add({ShaderType, PermId})

// Phase 2: Material shader pipelines
for each Pipeline in SortedMaterialPipelineTypes:
  if ShouldCompilePipeline(Pipeline, Platform, MaterialParams, Flags):
    Layout.ShaderPipelines.Add(Pipeline)

// Phase 3: Mesh material shaders (VF-dependent)
for each VFType in FVertexFactoryType::GetSortedMaterialTypes():
  MeshLayout = null
  for each ShaderType in SortedMeshMaterialShaderTypes:
    if !ShouldCompileVertexFactoryPermutation(VF, Shader, ...): skip
    for each PermutationId:
      if ShouldCompilePermutation(Platform, MaterialParams, VF, PermId, Flags):
        MeshLayout.Shaders.Add({ShaderType, PermId})

  for each Pipeline in SortedMeshMaterialPipelineTypes:
    if ShouldCompilePipeline(Pipeline, Platform, MaterialParams, VF, Flags):
      MeshLayout.ShaderPipelines.Add(Pipeline)
```

Output: `FMaterialShaderMapLayout { Shaders[], ShaderPipelines[], MeshShaderMaps[] }`

## 6. SubmitCompileJobs (Actual Compilation)

Source: MaterialShader.cpp L2474.

```
for each MeshLayout in Layout.MeshShaderMaps:
  FPipelinedShaderFilter filter(Platform, MeshLayout.ShaderPipelines)

  for each Shader in MeshLayout.Shaders:
    if !Material->ShouldCache(ShaderType, VF): skip        // Tier 1
    if filter.IsPipelinedType(ShaderType): skip             // already in pipeline
    if HasShader(ShaderType, PermId): skip                  // already compiled
    ShaderType->BeginCompileShader(...)

  for each Pipeline in MeshLayout.ShaderPipelines:
    if !Material->ShouldCachePipeline(Pipeline, VF): skip
    if Pipeline->ShouldOptimizeUnusedOutputs(Platform):
      BeginCompileShaderPipeline(...)  // unique shaders per pipeline
    else:
      // Share with standalone shaders via SharingPipelines map
```

## 7. Key Source Locations

| File | Lines | Content |
|------|-------|---------|
| Shader.h L1237-1566 | FShaderType class definition | Members, fn ptrs, GlobalListLink |
| Shader.h L1588-1607 | FShaderTypeRegistration | Deferred registration mechanism |
| Shader.h L1665-1743 | IMPLEMENT_SHADER_TYPE macro | Full expansion |
| Shader.h L1930-2036 | FShaderPipelineType | Stages, IMPLEMENT_SHADERPIPELINE macros |
| Shader.cpp L237-303 | FShaderType constructor | LinkHead + NameMap + SortedArray insert |
| Shader.cpp L327-335 | CommitAll() | Triggers lazy construction |
| Shader.cpp L462-464 | ShouldCompilePermutation | Freq check + fn ptr dispatch |
| VertexFactory.h L313-532 | FVertexFactoryType | Full definition + macros |
| MaterialShaderType.h L94-195 | FMaterialShaderType | ShouldCompilePermutation, BeginCompileShader |
| MeshMaterialShaderType.h L25-125 | FMeshMaterialShaderType | VF-aware compilation |
| MaterialShader.cpp L1965-1982 | ShouldCompilePermutation impl | Delegates to FShaderType base |
| MaterialShader.cpp L2474-2619 | SubmitCompileJobs | Three-tier filter + pipeline handling |
| MaterialShader.cpp L3162-3280 | CreateLayout | Full Layout collection with all types |
| GlobalShader.cpp L393-446 | Global shader iteration | GetTypeList traversal + ShouldCompile |
