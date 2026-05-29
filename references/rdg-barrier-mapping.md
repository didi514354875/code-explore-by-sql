# RDG Barrier Mapping: SubresourceState → ERHIAccess → D3D12 API

## Five-Layer Architecture

```
Layer 1: FRDGSubresourceState.Access (ERHIAccess)  — RDG per-subresource tracking
Layer 2: ERHIAccess (RHI platform-neutral bitmask)  — RHIAccess.h
Layer 3: ED3D12Access (D3D12 platform extension)    — D3D12Access.h (1:1 + Common/GenericRead)
Layer 4: D3D12_RESOURCE_STATES / D3D12_BARRIER_LAYOUT — D3D12 API types
Layer 5: ID3D12GraphicsCommandList::ResourceBarrier() / Barrier() — D3D12 API call
```

## Core Source Files

| File | Key Function |
|------|-------------|
| `RHI/Public/RHIAccess.h` | ERHIAccess enum (bitmask) |
| `D3D12RHI/Private/D3D12Access.h` | ED3D12Access (static_cast of ERHIAccess + Common/GenericRead), ConvertToD3D12Access() |
| `D3D12RHI/Private/D3D12LegacyBarriers.cpp` | GetD3D12ResourceState() (ED3D12Access → D3D12_RESOURCE_STATES), BeginTransitions/EndTransitions |
| `D3D12RHI/Private/D3D12EnhancedBarriers.cpp` | GetEBSync(), GetEBAccess(), GetEBLayout() (ERHIAccess → D3D12_BARRIER_SYNC/ACCESS/LAYOUT) |

## ERHIAccess → D3D12_RESOURCE_STATES (Legacy Barriers)

`GetD3D12ResourceState()` in D3D12LegacyBarriers.cpp:213-341

### Write States (switch exact match)

| ED3D12Access | D3D12_RESOURCE_STATES |
|---|---|
| Common | COMMON |
| RTV | RENDER_TARGET |
| UAVCompute / UAVGraphics / UAVMask | UNORDERED_ACCESS |
| DSVWrite | DEPTH_WRITE |
| CopyDest | COPY_DEST |
| ResolveDst | RESOLVE_DEST |
| Present | PRESENT |
| BVHRead / BVHWrite | RAYTRACING_ACCELERATION_STRUCTURE |
| Discard | Desc-dependent (RT→RENDER_TARGET, DS→DEPTH_WRITE, else→UAV) |

### Read States (bitwise OR accumulation)

| ED3D12Access bit | OR'd D3D12_RESOURCE_STATES | Note |
|---|---|---|
| SRVGraphics (Direct Queue) | PIXEL_SHADER_RESOURCE \| NON_PIXEL_SHADER_RESOURCE | Graphics = Pixel + NonPixel |
| SRVCompute | NON_PIXEL_SHADER_RESOURCE | Compute = NonPixel only |
| VertexOrIndexBuffer | VERTEX_AND_CONSTANT_BUFFER \| INDEX_BUFFER | |
| CopySrc | COPY_SOURCE | |
| IndirectArgs | INDIRECT_ARGUMENT | |
| ResolveSrc | RESOLVE_SOURCE | |
| DSVRead | DEPTH_READ | |
| ShadingRateSource | SHADING_RATE_SOURCE | PLATFORM_SUPPORTS_VARIABLE_RATE_SHADING |

### DSVRead+DSVWrite special case
→ Returns DEPTH_WRITE (depth write implies depth read in D3D12)

## UAV Barrier vs Cross-Pipeline SyncPoint

**These are two INDEPENDENT mechanisms that often co-occur but serve different purposes.**

### UAV Barrier (Cache Coherence)
- Trigger: AccessBefore has UAVMask AND AccessAfter has UAVMask
- Purpose: Flush GPU cache to make UAV writes visible to subsequent reads
- D3D12 API: `D3D12_RESOURCE_BARRIER_TYPE_UAV` with pResource=nullptr (global)
- Even needed on same Queue (compute unit caches)
- UE also calls `FlushComputeShaderCache(true)` when bUAVBarrier detected

### Cross-Pipeline SyncPoint (Queue Ordering)
- Trigger: SrcPipelines != DstPipelines (e.g. AsyncCompute → Graphics)
- Purpose: GPU Fence (Signal/Wait) to order execution across queues
- Created in CreateTransition as FD3D12SyncPoint per source pipeline
- Signal in BeginTransitions (source queue side)
- Wait in EndTransitions (destination queue side)

### Combined Example: AsyncCompute UAV → Graphics SRV

```
Compute Queue:
  BeginTransitions:
    Transition: UNORDERED_ACCESS → NON_PIXEL_SHADER_RESOURCE (Compute-only state)
    Signal(SyncPoint)

Graphics Queue:
  EndTransitions:
    Wait(SyncPoint)
    Transition: NON_PIXEL_SHADER_RESOURCE → PIXEL_SHADER_RESOURCE | NON_PIXEL_SHADER_RESOURCE
```

The transition is SPLIT across queues because D3D12 forbids Graphics-exclusive states on Compute Queue.

### bAsyncToAllPipelines Special Case

When SrcPipelines=AsyncCompute, DstPipelines=All, and AccessAfter contains SRVGraphics:
- Split into: AsyncCompute does UAV→SRVCompute, Graphics does SRVCompute→SRVMask
- On Graphics Queue, AccessBefore is forced to SRVCompute (not original UAV)
- AsyncCompute Signals, Graphics Waits

## Enhanced Barriers Path (D3D12_BARRIER_SYNC/ACCESS/LAYOUT)

### ERHIAccess → D3D12_BARRIER_SYNC (GetEBSync)

| ED3D12Access | D3D12_BARRIER_SYNC |
|---|---|
| UAVCompute | COMPUTE_SHADING |
| UAVGraphics | VERTEX_SHADING \| PIXEL_SHADING |
| RTV | RENDER_TARGET |
| DSVWrite | DEPTH_STENCIL |
| DSVRead | DEPTH_STENCIL |
| SRVCompute | COMPUTE_SHADING |
| SRVGraphicsPixel | PIXEL_SHADING |
| SRVGraphicsNonPixel | NON_PIXEL_SHADING |
| CopySrc / CopyDest | COPY |
| ResolveSrc / ResolveDst | RESOLVE |
| IndirectArgs | EXECUTE_INDIRECT |
| VertexOrIndexBuffer | VERTEX_SHADING \| INDEX_INPUT \| ALL_SHADING |
| Discard | SYNC_NONE |
| Common / GenericRead / Unknown | SYNC_ALL |

### ERHIAccess → D3D12_BARRIER_ACCESS (GetEBAccess)

| ED3D12Access | D3D12_BARRIER_ACCESS |
|---|---|
| UAVMask | UNORDERED_ACCESS |
| RTV | RENDER_TARGET |
| DSVWrite | DEPTH_STENCIL_WRITE |
| DSVRead | DEPTH_STENCIL_READ |
| SRVMask | SHADER_RESOURCE |
| CopySrc | COPY_SOURCE |
| CopyDest | COPY_DEST |
| VertexOrIndexBuffer | VERTEX_BUFFER \| INDEX_BUFFER \| CONSTANT_BUFFER |
| IndirectArgs | INDIRECT_ARGUMENT |
| BVHRead | RAYTRACING_ACCELERATION_STRUCTURE_READ |
| BVHWrite | RAYTRACING_ACCELERATION_STRUCTURE_WRITE |
| Discard | NO_ACCESS |
| Common / Unknown | COMMON |

### ERHIAccess → D3D12_BARRIER_LAYOUT (GetEBLayout, textures only)

| ED3D12Access | Graphics Queue | Compute Queue | All |
|---|---|---|---|
| RTV | RENDER_TARGET | — | — |
| UAVMask | DIRECT_QUEUE_UNORDERED_ACCESS | COMPUTE_QUEUE_UNORDERED_ACCESS | UNORDERED_ACCESS |
| SRVMask | DIRECT_QUEUE_SHADER_RESOURCE | COMPUTE_QUEUE_SHADER_RESOURCE | SHADER_RESOURCE |
| DSVWrite | DEPTH_STENCIL_WRITE | — | — |
| DSVRead | DEPTH_STENCIL_READ | — | — |
| CopyDest | DIRECT_QUEUE_COPY_DEST | COMPUTE_QUEUE_COPY_DEST | COPY_DEST |
| CopySrc | DIRECT_QUEUE_COPY_SOURCE | COMPUTE_QUEUE_COPY_SOURCE | COPY_SOURCE |
| Discard | UNDEFINED | UNDEFINED | UNDEFINED |

Layouts are queue-specific when possible (DIRECT_QUEUE_* / COMPUTE_QUEUE_*).

### UAV→UAV Skip Rule (Enhanced Barriers)
`BarrierCanBeDiscard()`: Even when Sync/Access/Layout are identical, barriers where Before is "compute write" (UAV/RTAS write + compute sync scope) CANNOT be discarded — each compute unit may have independent caches.

## Barrier Type Summary

| D3D12_RESOURCE_BARRIER_TYPE | When Used |
|---|---|
| TRANSITION | StateBefore != StateAfter (resource state change) |
| UAV | AccessBefore & UAVMask && AccessAfter & UAVMask (cache flush, pResource can be null) |
| ALIASING | Transient resource acquire/release (pResourceBefore→pResourceAfter) |
