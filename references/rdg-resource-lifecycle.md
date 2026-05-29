# FRDGBuilder Texture/Buffer Resource Lifecycle

## Core Files

| File | Purpose |
|------|---------|
| `RenderCore/Public/RenderGraphBuilder.h` | FRDGBuilder class definition, CreateTexture/CreateBuffer API |
| `RenderCore/Public/RenderGraphResources.h` | FRDGTexture, FRDGBuffer, FRDGView, FRDGViewableResource |
| `RenderCore/Public/RenderGraphDefinitions.h` | Handle types, flags, enums |
| `RenderCore/Private/RenderGraphResourcePool.h` | FRDGBufferPool, FRDGTransientResourceAllocator |
| `RenderCore/Private/RenderGraphBuilder.cpp` | Execute(), allocation, culling implementation |
| `RenderCore/Private/RenderGraphResources.cpp` | Resource initialization |
| `RenderCore/Private/RenderGraphPrivate.h` | Internal data structures |

## Class Hierarchy

```
FRDGResource (Name, ResourceRHI)
├── FRDGUniformBuffer
└── FRDGViewableResource (bExternal, bExtracted, bTransient, ReferenceCount)
    ├── FRDGTexture (Desc, Handle, RenderTarget, TransientTexture, ViewCache, Allocation)
    └── FRDGBuffer (Desc, Handle, PooledBuffer, TransientBuffer, ViewCache, Allocation)

FRDGView
├── FRDGShaderResourceView
│   ├── FRDGTextureSRV
│   └── FRDGBufferSRV
└── FRDGUnorderedAccessView
    ├── FRDGTextureUAV
    └── FRDGBufferUAV
```

## Three-Phase Lifecycle

### Phase 1: Setup (user code, before Execute)
- `CreateTexture(desc)` / `CreateBuffer(desc)` → register descriptor, NO GPU allocation
- `CreateSRV/UAV` → register view descriptor
- `RegisterExternalTexture/Buffer` → wrap pre-existing pooled resource
- `AddPass(params, lambda)` → scan _RDG params, increment ReferenceCount
- `QueueTextureExtraction/BufferExtraction` → mark for lifetime extension

### Phase 2: Compile + Execute (inside Execute())
1. **Culling**: ReferenceCount==0 → resource/pass removed
2. **Lifetime computation**: FirstPass/LastPass per resource
3. **Barrier planning**: Subresource state transitions auto-computed
4. **Per-pass allocation**:
   - Allocate resources on first-use pass
   - Deallocate on last-use pass
5. **Two-tier GPU allocation**:
   - **Transient Allocator** (preferred): IRHITransientResourceAllocator, GPU memory aliasing
   - **Pooled Allocator** (fallback): FRDGBufferPool / FRenderTargetPool, reuse across frames
6. **Pass execution**: Prologue barrier → lambda → Epilogue barrier

### Phase 3: Epilogue + Cleanup
- Extraction: transfer Pooled resource ownership to external pointers
- Resource return: pooled resources go back to pool, transient resources deallocated
- CPU memory: FRDGAllocator destructor frees all RDG-allocated objects

## Key Allocation Paths

### Texture
```
IsTransient(Texture)?
  YES → TransientResourceAllocator->AllocateTexture → FRHITransientTexture → SetTransientTextureRHI
  NO  → AllocatePooledRenderTargetRHI → FRenderTargetPool → FRDGPooledTexture → SetPooledTextureRHI
```

### Buffer
```
IsTransient(Buffer)?
  YES → TransientResourceAllocator->AllocateBuffer → FRHITransientBuffer → SetTransientBufferRHI
  NO  → GRenderGraphResourcePool.FindFreeBuffer → FRDGPooledBuffer → SetPooledBufferRHI
```

## FRDGBufferDesc Factory Methods

| Method | Usage Flags | Typical Use |
|--------|------------|-------------|
| `CreateStructuredDesc` | UAV+SRV+StructuredBuffer | GPU compute read/write |
| `CreateByteAddressDesc` | UAV+SRV+ByteAddress+StructuredBuffer | Raw byte access |
| `CreateBufferDesc` | UAV+SRV+VertexBuffer | Vertex data |
| `CreateIndirectDesc` | DrawIndirect+UAV+SRV+VB | Indirect draw/dispatch args |
| `CreateUploadDesc` | SRV+VertexBuffer | CPU→GPU upload |
| `CreateStructuredUploadDesc` | SRV+StructuredBuffer | CPU→GPU structured upload |

## State Tracking

- `FRDGSubresourceState`: Access, FirstPass, LastPass, NoUAVBarrierFilter
- Texture: per-subresource (mip × slice) state arrays
- Buffer: single subresource state
- `FRDGProducerStatesByPipeline`: tracks which pass last wrote to each subresource per pipeline (Graphics/AsyncCompute)

## Aliasing

- `PreviousOwner` / `NextOwner` handles form a chain of RDG resources sharing the same pooled allocation
- Transient allocator uses GPU-level memory aliasing (D3D12 Placed Resources / Vulkan memory aliasing)
- Temporal non-overlap = same physical memory reused
