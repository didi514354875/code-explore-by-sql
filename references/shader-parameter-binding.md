# Shader Parameter Binding: C++ → HLSL → Runtime

## Overview

Five-stage pipeline connecting C++ shader parameter declarations to GPU shader variables:

```
C++ SHADER_PARAMETER macros
  → FShaderParametersMetadata (compile-time reflection)
    → [EDITOR] HLSL cbuffer/struct code generation (GeneratedUniformBuffers.ush)
      → Shader compilation + reflection → FShaderParameterMap
        → C++ Bind → FShaderParameterBindings (offset mapping table)
          → Runtime: memcpy CB data + bind resources via RHI
```

## Core Source Files

| File | Role |
|------|------|
| `RenderCore/Public/ShaderParameterMacros.h` | SHADER_PARAMETER macro definitions, TUniformBufferRef, RDG access types |
| `RenderCore/Public/ShaderParameterStructDeclaration.h` | BEGIN_SHADER_PARAMETER_STRUCT expansion, forward declarations |
| `RenderCore/Public/ShaderParameterMetadata.h` | FShaderParametersMetadata class, FMember (Name, Offset, BaseType, ShaderType) |
| `RenderCore/Private/ShaderParameters.cpp` | CreateHLSLUniformBufferDeclaration(), GeneratedUniformBuffers.ush generation, ModifyCompilationEnvironment() |
| `RenderCore/Private/ShaderParameterStruct.cpp` | FShaderParameterStructBindingContext::Bind(), BindForLegacyShaderParameters(), BindForRootShaderParameters() |
| `RenderCore/Public/Shader.h` | FShaderParameterBindings class (Parameters, ResourceParameters, ParameterReferences) |

## Stage 1: C++ Macro Expansion

### SHADER_PARAMETER macro generates three things:
1. **C++ struct member** — actual field with correct offset/alignment
2. **FShaderParametersMetadata::FMember** — reflection entry with Name, ShaderType, Offset, BaseType, NumRows, NumColumns, NumElements
3. **FTypeInfo::GetStructMetadata()** — static accessor for the metadata

### Key BaseType values (EUniformBufferBaseType):
- `UBMT_FLOAT32/INT32/UINT32` — scalar/vector/matrix constants
- `UBMT_TEXTURE/UBMT_SRV/UBMT_UAV/UBMT_SAMPLER` — RHI resource bindings
- `UBMT_RDG_TEXTURE_SRV/UBMT_RDG_BUFFER_UAV` etc. — RDG resource references (pointers)
- `UBMT_NESTED_STRUCT/UBMT_INCLUDED_STRUCT` — nested parameter structs
- `UBMT_REFERENCED_STRUCT` — externally referenced UniformBuffer
- `UBMT_RENDER_TARGET_BINDING_SLOTS` — render target bindings (special)

### RDG access types are skipped during Bind:
```cpp
if (IsRDGResourceAccessType(BaseType)) continue; // pointers, not shader-visible
```

## Stage 2: HLSL Code Generation (EDITOR only)

`CreateHLSLUniformBufferDeclaration()` in ShaderParameters.cpp:375-418

### Generated structure:
```hlsl
// /Engine/Generated/UniformBuffers/<StructName>.ush
UB_CB_DEFINITION_START(StructName)
    UB_FLOAT(4x4) UB_CB_MEMBER_NAME(StructName, Field1);
    UB_FLOAT(4) UB_CB_MEMBER_NAME(StructName, Field2);
    // Padding inserted when C++ offset != HLSL offset
    UB_FLOAT() UB_CB_MEMBER_NAME(StructName, Padding84);
UB_CB_DEFINITION_END(StructName)
UB_RESOURCE_MEMBER_SRV(Texture2D, StructName, TextureField);
UB_RESOURCE_MEMBER_UAV(RWBuffer<float>, StructName, UAVField);

UniformBuffer StructName {
    UB_CB_DECL_PARAMETER(StructName, Field1, Field1);
    UB_CB_DECL_RESOURCE(StructName, TextureField, TextureField);
};
```

### Layout consistency:
- `HLSLBaseOffset` tracks current HLSL byte position
- Compares against `StructOffset + Member.GetOffset()` (C++ offset)
- Inserts `Padding<N>` members when HLSL falls behind
- Array elements: flattened to `FieldName_0`, `FieldName_1`, ...
- Nested structs: prefixed as `NestedStruct_MemberName`

### Aggregation:
All generated `.ush` files included via `/Engine/Generated/GeneratedUniformBuffers.ush`, which is included by `Common.ush` → available to all shaders.

### UniformBuffer includes injected via:
```cpp
FShaderUniformBufferParameter::ModifyCompilationEnvironment()
  → Creates virtual .ush file in IncludeVirtualPathToContentsMap
  → Appends #include to GeneratedUniformBuffers.ush
  → Calls AddResourceTableEntries() for resource table layout
```

## Stage 3: Shader Compilation & Reflection

```
.usf/.ush source + Generated UniformBuffers + Material template
  → ShaderCompileWorker (separate process)
  → HLSL → DXC/FXC → DXIL/DXBC
  → D3D reflection extracts parameter info
  → UE post-processing creates FShaderParameterMap
```

### FShaderParameterMap entries:
```cpp
struct FParameterAllocation {
    uint16 BufferIndex;         // which cbuffer (register b#)
    uint16 BaseIndex;           // byte offset in cbuffer / register number for resources
    uint16 Size;                // bytes or resource count
    EShaderParameterType Type;  // LooseData, SRV, UAV, Sampler, etc.
};
// Keyed by HLSL parameter name (e.g. "WorldToClip", "NestedStruct_Field")
```

Parameters optimized away by the HLSL compiler are NOT in the map → auto-skipped in Bind.

## Stage 4: C++ Bind — Building the Offset Map

`FShaderParameterStructBindingContext::Bind()` in ShaderParameterStruct.cpp:46-247

### Binding process:
```
For each FMember in FShaderParametersMetadata:
  Compute ShaderBindingName from Member.GetName() + nesting prefix
  Lookup in FShaderParameterMap by name
  If found, create binding entry:
    - Constants → Bindings.Parameters (BufferIndex, BaseIndex=HLSL offset, ByteOffset=C++ offset, ByteSize)
    - Resources → Bindings.ResourceParameters (BaseIndex=register#, ByteOffset=C++ pointer offset, BaseType)
    - Bindless → Bindings.BindlessResourceParameters
    - Referenced UB → Bindings.ParameterReferences
    - RDG UB → Bindings.GraphUniformBuffers
```

### Four binding categories in FShaderParameterBindings:
1. **Parameters[]** — scalar/vector/matrix constants (memcpy CB data)
2. **ResourceParameters[]** — SRV/UAV/Sampler (RHI resource binding)
3. **BindlessResourceParameters[]** — bindless resources (index in global CB)
4. **ParameterReferences[] / GraphUniformBuffers[]** — UniformBuffer references

### Root Shader Parameters:
When `_RootShaderParameters` exists in ParameterMap, constants go into root CB at index 0.
`bUseRootShaderParameters` flag controls this path.

## Stage 5: Runtime Data Transfer

### RDG Pass execution:
```
1. User fills FMyPassParameters* Params = GraphBuilder.AllocParameters<FMyPassParameters>()
   Params->WorldToClip = matrix;      // C++ offset 0
   Params->DepthTexture = RDGSRV;     // C++ offset 160 (pointer)

2. SetParameters() iterates Bindings:
   For Parameters[]:
     memcpy(CB_data + BaseIndex, (char*)Params + ByteOffset, ByteSize)
     → RHISetShaderParameter(BufferIndex, BaseIndex, data, size)
   
   For ResourceParameters[]:
     FRHITextureSRV* srv = *(FRHITextureSRV**)((char*)Params + ByteOffset)
     → RHISetShaderResource(BaseIndex, srv)
   
   For ParameterReferences[]:
     FRHIUniformBuffer* ub = *(...)((char*)Params + ByteOffset)
     → RHISetUniformBuffer(BaseIndex, ub)
```

### Resource dereferencing chain (RDG):
```
C++ FRDGTextureSRV* → GraphBuilder.Execute() resolves → FRHITextureSRV* → bound to register(t#)
```

## Material Shader Specialization

Material parameters follow the same pipeline with an extra code-gen step:
```
Material Editor node graph
  → UMaterial::CompileProperty() → FMaterialCompiler
  → Generates HLSL function bodies replacing %MaterialParameters% etc. in MaterialTemplate.usf
  → Material UniformBuffer (FMaterialUniformParameters) also uses BEGIN_SHADER_PARAMETER_STRUCT
  → Merges into same compilation → reflection → binding pipeline
```

## Stage 6: Resource Pointer Dereferencing (ExtractShaderParameterResource)

Source: `ShaderParameterStruct.cpp:616-674`

At runtime, `ExtractShaderParameterResource()` reads the pointer at `ByteOffset` in the C++ struct and dereferences it based on `BaseType`:

```cpp
switch (BaseType)
{
case UBMT_TEXTURE:
    return Resource(Reader.Read<FRHITexture*>(Parameter), register_index);        // direct RHI ptr
case UBMT_SRV:
    return Resource(Reader.Read<FRHIShaderResourceView*>(Parameter), register_index);
case UBMT_RDG_TEXTURE:
    RDGTexture = Reader.Read<FRDGTexture*>(Parameter);
    RDGTexture->MarkResourceAsUsed();
    return Resource(RDGTexture->GetRHI(), register_index);                        // RDG → RHI
case UBMT_RDG_TEXTURE_SRV:
case UBMT_RDG_BUFFER_SRV:
    RDGSRV = Reader.Read<FRDGShaderResourceView*>(Parameter);
    RDGSRV->MarkResourceAsUsed();
    return Resource(RDGSRV->GetRHI(), register_index);                            // RDG → RHI
case UBMT_RDG_TEXTURE_UAV:
case UBMT_RDG_BUFFER_UAV:
    RDGUAV = Reader.Read<FRDGUnorderedAccessView*>(Parameter);
    RDGUAV->MarkResourceAsUsed();
    return Resource(RDGUAV->GetRHI(), register_index);                            // RDG → RHI
}
```

Two classes of pointer:
- **RHI types** (`UBMT_TEXTURE/SRV/UAV/SAMPLER`): pointer IS the RHI resource, use directly
- **RDG types** (`UBMT_RDG_*`): must call `->GetRHI()` to get underlying RHI resource, plus `->MarkResourceAsUsed()` for RDG dependency tracking

Result is packed into `FRHIShaderParameterResource` and batched via `FRHIBatchedShaderParameters::AddResourceParameter()` → ultimately `SetSRV/SetUAV/SetSampler/SetTexture` on the command list.

## Stage 7: Unused Parameter Culling & Alignment

### Why culling does NOT affect alignment

**C++ struct offsets are physical, immutable facts.** The macro uses `STRUCT_OFFSET(zzTThisStruct, MemberName)` (= `offsetof`) to record each member's byte offset at C++ compile time. This value is baked into `FMember::Offset` and never changes.

Culling works at the **mapping layer**, not the layout layer:
1. HLSL compiler optimizes away unused variables → they disappear from `FShaderParameterMap`
2. Bind phase: `FindParameterAllocation(name)` returns empty for optimized-away params → `continue` (skip)
3. Runtime: `SetShaderParameters` only iterates `Bindings.Parameters` and `Bindings.ResourceParameters` (the mapping table, not the struct). Each entry carries its own `ByteOffset` — absolute position in the C++ struct.
4. **Skipping offset X does not shift offset Y.** The mapping is by-value lookup, not sequential.

```
C++ struct (immutable):       Bindings mapping (per-shader):
offset=0:  Matrix (64B)      Parameters[0]: C++off=0 → CB[0]+0
offset=64: Vector (16B)      Parameters[1]: C++off=64 → CB[0]+64
offset=80: RDGSRV* (8B)      ResourceParams[0]: C++off=80 → t0
offset=88: RDGUAV* (8B)      ResourceParams[1]: C++off=88 → u0
offset=96: RDGSRV* (8B)      (not in bindings — HLSL optimized away)
```

### ClearUnusedGraphResources (RenderGraphUtils.cpp:15-93)

After Bind, RDG calls `ClearUnusedGraphResourcesImpl()` which nulls out RDG resource pointers whose `ByteOffset` is NOT present in any `ShaderBindings.ResourceParameters` or `BindlessResourceParameters`:

```cpp
for (GraphResource in Metadata.Layout.GraphResources)
{
    ByteOffset = GraphResource.MemberOffset;
    // Binary search in ShaderBindings.ResourceParameters by ByteOffset
    if (found in ResourceParameters or BindlessResourceParameters or GraphUniformBuffers)
        continue;   // shader uses this resource

    *reinterpret_cast<FRDGResourceRef*>(Base + ByteOffset) = nullptr;
}
```

**Purpose**: Setting the pointer to `nullptr` causes RDG dependency analysis to see 0 references for that texture/buffer → RDG culling skips GPU allocation for the resource entirely. This is a **performance optimization**, not a correctness requirement.

### Validation (DO_CHECK builds)

`ValidateShaderParameters()` in ShaderParameterStruct.cpp:507-587 only checks resources that ARE in `Bindings.ResourceParameters`. If a parameter was optimized away (not in bindings), it is never validated — the pointer value doesn't matter.

If a parameter IS in bindings but the pointer is null → `EmitNullShaderParameterFatalError` (crash). This catches "declared but forgot to assign" bugs.

## Design Principles

1. **Name matching**: C++ macro Name = HLSL variable name = FShaderParameterMap key
2. **Layout parity**: C++ struct and HLSL cbuffer must have identical byte layout (padding auto-generated)
3. **Dead-stripping**: HLSL compiler optimizations remove unused parameters from ParameterMap; Bind skips them silently
4. **RDG integration**: RDG pointer types (FRDGTextureSRV* etc.) are invisible to shader — dereferenced by ExtractShaderParameterResource via GetRHI() before binding
5. **Material sharing**: Same UniformBuffer infrastructure serves both Global and Material shaders
6. **Offset immutability**: STRUCT_OFFSET values are compile-time constants. Culling operates on the mapping table, not the C++ struct layout. Skipping a member never shifts other members' offsets.
7. **ClearUnusedGraphResources**: Nulls RDG resource pointers for shader-optimized-away params → enables RDG allocation culling (VRAM savings)
