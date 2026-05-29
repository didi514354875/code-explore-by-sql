# Virtual Texture System Architecture Analysis

## Overview

Unreal Engine's Virtual Texture (VT) system implements a **sparse texture residency** model inspired by hardware virtual memory: large textures are stored as a multi-resolution page table, and only the visible pages (tiles) needed for the current viewpoint are loaded into a bounded physical texture cache on the GPU.

The system spans three major layers:
1. **Asset/UObject layer** (Engine module) — texture assets, components, build settings
2. **RenderCore interface layer** (RenderCore module) — stable abstract interfaces shared across renderer backends
3. **Renderer implementation layer** (Renderer module) — concrete VT system, page tables, feedback, physical pools

---

## Layer 1: Asset & UObject Layer

### UTexture2D (base)
`UVirtualTexture2D` **inherits from** `UTexture2D`, not from `UVirtualTexture`. The old `UVirtualTexture` is a **deprecated** stub (`UObject` subclass).

```
UObject
 └── UTexture
      └── UTexture2D
           └── UVirtualTexture2D   (SVT - streaming virtual texture from disk)
```

`UVirtualTexture2D` adds `FVirtualTextureBuildSettings` and `bSinglePhysicalSpace` for build configuration.

### URuntimeVirtualTexture (RVT)
Runtime Virtual Textures are **procedurally generated** at runtime (e.g., landscape material baked into VT). The key class chain:

```
UObject
 └── UTexture
      └── URuntimeVirtualTexture
```

### URuntimeVirtualTextureComponent
A `USceneComponent` placed in the world to:
- Define world-space bounds (align to landscape, etc.)
- Hold a reference to a `URuntimeVirtualTexture` asset
- Create `FRuntimeVirtualTextureSceneProxy` for the renderer

### LightmapVirtualTexture
`ULightMapVirtualTexture` (deprecated base) / current lightmap VT — uses VT to store baked lightmaps at massive resolution.

### VirtualTextureBuilder
Editor-time tool (`UVirtualTextureBuilder`) to pre-build VT data from source textures.

---

## Layer 2: RenderCore Interfaces (VirtualTexturing.h)

This is the **stable public API** that decouples the Engine module from the Renderer implementation.

### IVirtualTexture (Producer Interface)
The core abstraction for **tile data generation**:

```cpp
class IVirtualTexture {
    virtual uint32 GetLocalMipBias(uint8 vLevel, uint32 vAddress) const;
    virtual bool IsPageStreamed(uint8 vLevel, uint32 vAddress) const = 0;
    virtual FVTRequestPageResult RequestPageData(
        FRHICommandListBase&, const FVirtualTextureProducerHandle&,
        uint8 LayerMask, uint8 vLevel, uint64 vAddress, EVTRequestPagePriority) = 0;
    virtual IVirtualTextureFinalizer* ProducePageData(
        FRHICommandListBase&, ERHIFeatureLevel, EVTProducePageFlags,
        const FVirtualTextureProducerHandle&, uint8 LayerMask,
        uint8 vLevel, uint64 vAddress, uint64 RequestHandle,
        const FVTProduceTargetLayer*) = 0;
};
```

**Two-phase tile production:**
1. `RequestPageData()` — Check if data is Available/Pending/Saturated/Invalid
2. `ProducePageData()` — Actually generate tile data, return a Finalizer

### IVirtualTextureFinalizer
Two-phase finalization for GPU hazard avoidance:
- `RenderFinalize()` — Read-only pass (can sample other VTs, used by RVT and material system)
- `Finalize()` — Write-only pass (writes to physical texture pools)

### IAllocatedVirtualTexture
Represents an allocated VT in the renderer, backed by page table textures + physical texture cache. Provides:
- `GetPageTableTexture()`, `GetPhysicalTexture()`, `GetPhysicalTextureSRV()`
- `GetPackedPageTableUniform()` — shader constants for page table lookup
- `GetPackedUniform()` — per-layer shader constants

### Key Data Structures

| Struct | Purpose |
|--------|---------|
| `FVirtualTextureProducerHandle` | 32-bit handle (22-bit index + 10-bit magic) to a producer |
| `FAllocatedVTDescription` | Parameters to allocate a VT: tile size, border, layers, producer handles |
| `FVTProducerDescription` | Producer metadata: dimensions, block layout, layer formats, physical groups |
| `FVTRequestPageResult` | Result of page request: {Handle, Status} |
| `FVTProduceTargetLayer` | Where to write tile data: {PooledRenderTarget, pPageLocation} |

### Constants
- `VIRTUALTEXTURE_MAX_PAGETABLE_SIZE` = 4096 (12-bit log2)
- `VIRTUALTEXTURE_MAX_FEEDBACK_SPACES` = 16
- `VIRTUALTEXTURE_SPACE_MAXLAYERS` = 8
- `LayersPerPageTableTexture` = 4

---

## Layer 3: Renderer Implementation (Renderer/Private/VT/)

### FVirtualTextureSystem (Central Coordinator)
The singleton that orchestrates all VT operations per frame:

```
FVirtualTextureSystem
 ├── Owns: FVirtualTextureSpace[]       (page table address spaces)
 ├── Owns: FVirtualTexturePhysicalSpace[] (physical tile pools)
 ├── Owns: FVirtualTextureProducer[]     (producer wrappers)
 ├── Owns: FAllocatedVirtualTexture[]    (allocated VT instances)
 ├── Owns: FAdaptiveVirtualTexture[]     (adaptive VT instances)
 ├── Uses: FVirtualTextureFeedback       (GPU→CPU feedback pipeline)
 └── Uses: FUniqueRequestList            (deduplicated page requests)
```

Frame update flow (`BeginUpdate()` internal sequence, `VirtualTextureSystem.cpp:2994`):
1. `CallPendingCallbacks()` — execute pending destroy callbacks (called in `UpdateAllPrimitiveSceneInfos`, before `BeginUpdate`)
2. `BeginUpdate()` — main entry point, returns `FVirtualTextureUpdater`:
   - `AllocateResources()` — ensure GPU resources ready
   - `AdaptiveVTs[].UpdateAllocations()` — grow/shrink adaptive VT sub-allocations
   - `DestroyPendingVirtualTextures()` + `ReleasePendingSpaces()` — deferred cleanup
   - `Scene->FlushDirtyRuntimeVirtualTextures()` — only if feedback is available (`GVirtualTextureFeedback.CanMap()`), prevents visible glitching at low FPS
   - Creates `FVirtualTextureUpdater` with throttling budgets
   - Optionally kicks async tasks (`BeginUpdate(GraphBuilder, Updater)`)
3. **Feedback analysis** — `FVirtualTextureFeedbackBufferResource` compacts feedback on GPU, readback to CPU
4. **Request gathering** — `FFeedbackAnalysisTask` + `FGatherRequestsTask` build `FUniqueRequestList`
5. **Page production** — `FAddRequestedTilesTask` calls `RequestPageData` / `ProducePageData` on producers
6. `WaitForTasks()` — wait for async `UE::Tasks::FTask`
7. `EndUpdate()` — **Finalization**: Execute `RenderFinalize` then `Finalize` passes on all Finalizers
8. **Page table update** — `Space.ApplyUpdates()` via `PageTableUpdate.usf` writes new mappings
9. `FinalizeRequests()` — cleanup after page table update
10. `ReleasePendingResources()` — deferred resource cleanup
11. `GrowPhysicalPools()` — auto-grow physical pools when oversubscribed (if `r.VT.PoolAutoGrow` enabled)
12. `UpdateResidencyTracking()` — update residency mip bias per physical space

### FVirtualTextureSpace (Page Table Address Space)
- Maps virtual addresses to physical tile locations
- Backed by GPU page table textures (R16G16 or R32G32 formats)
- Shared among multiple `FAllocatedVirtualTexture` instances with compatible layouts
- Description: `FVTSpaceDescription` {TileSize, TileBorderSize, Dimensions, PageTableFormat, NumPageTableLayers, ...}

### FVirtualTexturePhysicalSpace (Physical Tile Pool)
- GPU texture pool that holds resident tile data (`FRenderResource` subclass)
- Manages a `FTexturePagePool` for tile allocation/eviction
- Multiple physical spaces can exist (different formats, sizes)
- `FVTPhysicalSpaceDescription` defines: {TileSize, NumLayers, Format[], bCanSplit, bHasLayerSrgbView[]}
- `FVTPhysicalSpaceDescriptionExt` adds: {TileWidthHeight, PoolCount, ResidencyMipMapBias, ResidencyMipMapBiasGroup}
- Physical texture layout: square atlas of `SizeInTiles × SizeInTiles`, each tile is `TileSize × TileSize`
- `GetPhysicalLocation(pAddress)` converts linear page index to (x, y) position in atlas

### FVirtualTextureProducer (Producer Wrapper)
- Wraps an `IVirtualTexture*` with additional bookkeeping
- Tracks physical spaces per physical group
- Manages locked mip counts (for always-resident mips)
- Key methods: `Release()`, `GetPhysicalSpaceForPhysicalGroup()`, `GetLayerFormat()`

### FAllocatedVirtualTexture
- Concrete implementation of `IAllocatedVirtualTexture`
- Assigned a virtual address within a `FVirtualTextureSpace`
- Lock/unlock tiles, map locked tiles
- Provides page table uniforms for shader consumption
- Constructor takes: System, Frame, FAllocatedVTDescription, Producer array, block/tile dimensions

### FAdaptiveVirtualTexture
- Implements adaptive resolution VT (used by Runtime VT)
- Splits VT into a grid of UV ranges, each with independent resolution
- Uses additional **indirection texture** (`IndirectVirtualTexture.ush`) for UV→page-table remapping
- Feedback-driven: increases/decreases resolution per UV range
- Avoids regeneration cost by directly remapping page table entries

### FVirtualTextureFeedback (GPU→CPU Pipeline)
- Collects per-pixel VT feedback during rendering (which pages were sampled)
- GPU buffer → CPU readback via `TransferGPUToCPU()`
- `Map()` returns feedback data as {PageId, PageCount} pairs
- Analysis extracts unique page requests

### FTexturePagePool + FTexturePageMap (Page Management)

**FTexturePagePool** (`TexturePagePool.h/.cpp`):
- Manages a pool of texture pages backed by a large GPU texture atlas
- Pages allocated per-producer, mapped into virtual page tables
- Tracks ownership (which VT allocated each page) and all page table mappings
- Key methods: `Initialize(NumPages)`, `EvictAllPages()`, `EvictPages(ProducerHandle)`
- Maintains `FreeHeap` for available pages, `NumPagesAllocated`/`NumPagesMapped` counters
- Thread-safe via `FCriticalSection`

**FTexturePageMap** (`TexturePageMap.h/.cpp`):
- Tracks virtual→physical address mappings for a single layer of a page table
- Key methods: `FindPageAddress(vLogSize, vAddress)`, `FindBestPageAddress()` (mip fallback chain)
- vLogSize = mip level of virtual address space; vLevel = mip level of producer being mapped
- These can differ (e.g., ancestor page at higher vLevel mapped to same address, or layer size mismatch with mip bias)
- Page mapping/unmapping must go through FTexturePagePool, not directly

### FVirtualTextureUpdater + Update Throttling

**FVirtualTextureUpdater** — per-frame update context:
- Holds `FVirtualTextureUpdateSettings`, merged request list, feedback map result, async task handle
- Budget counters: `PageUploadBudgetRVT`, `PageUploadBudgetSVT`

**FVirtualTextureUpdateSettings** — throttling config:
- `MaxRVTPageUploads` / `MaxSVTPageUploads` — per-frame page upload limits
- `MaxPagesProduced` — total production cap
- `MaxContinuousUpdates` — continuous update limit
- `bEnableAsyncTasks` — async task pipeline toggle
- `bEnablePageRequests` — disable feedback-driven updates (for playback etc.)
- `bForceSyncPageUpdate` — force synchronous page updates
- `EnableThrottling(false)` sets all limits to 99999 for unthrottled mode

---

## GPU / Shader Layer

### Page Table Lookup (Material Sampling)
`VirtualTextureMaterial.ush/.usf` — Material shader code that:
1. Calculates mip level from screen-space derivatives
2. Looks up page table texture using virtual address
3. Falls back to lower mip if page not resident
4. Writes feedback (visible page request) to feedback buffer

### Page Table Update
`PageTableUpdate.usf` — Compute/vertex shader that:
1. Reads `UpdateBuffer` (packed: vAddress, pPage, vLevel, vLogSize)
2. Decodes morton-coded virtual addresses
3. Renders quads into page table texture to map virtual→physical

### Indirect Virtual Texture
`IndirectVirtualTexture.ush` + `IndirectVirtualTextureDefinitions.h` —
Shader type `Buffer<uint2>` used by adaptive VT for the indirection lookup.

---

## Two VT Paradigms

### Streaming Virtual Texture (SVT)
- Data comes from disk (pre-built tiles in `.uasset` / `.utexture`)
- `IVirtualTexture::IsPageStreamed()` returns true
- RequestPageData → IO request → ProducePageData when loaded
- Managed by `UVirtualTexture2D` asset

### Runtime Virtual Texture (RVT)
- Data generated procedurally at runtime (e.g., landscape materials)
- `URuntimeVirtualTexture` + `URuntimeVirtualTextureComponent`
- `FRuntimeVirtualTextureSceneProxy` manages renderer-side state
- Uses `FAdaptiveVirtualTexture` for adaptive resolution
- RenderFinalize phase allows sampling other VTs during production

---

## Architecture Diagram

```
┌─────────────────── UObject Layer ───────────────────┐
│  UVirtualTexture2D ──(SVT)──┐                       │
│  URuntimeVirtualTexture ─────┤  URuntimeVirtualTextureComponent
│  ULightMapVirtualTexture ────┘       │                │
└──────────────────────────────────────┼────────────────┘
                                       │ creates
┌─────────────────── RenderCore Interfaces ────────────┐
│  IVirtualTexture (producer)                          │
│  IVirtualTextureFinalizer (GPU write scheduling)     │
│  IAllocatedVirtualTexture (page table + physical)    │
│  FVirtualTextureProducerHandle (32-bit ID)           │
└──────────────────────────────────────────────────────┘
                                       │ implemented by
┌─────────────────── Renderer/VT ──────────────────────┐
│  FVirtualTextureSystem ────────── central coordinator │
│    ├── FVirtualTextureSpace[]     page table spaces   │
│    ├── FVirtualTexturePhysicalSpace[]  tile pools     │
│    ├── FAllocatedVirtualTexture[]  VT instances       │
│    ├── FAdaptiveVirtualTexture[]   adaptive RVTs      │
│    └── FVirtualTextureFeedback     GPU→CPU pipeline   │
│  FVirtualTextureProducer          producer wrapper    │
│  FRuntimeVirtualTextureSceneProxy RVT scene proxy     │
└──────────────────────────────────────────────────────┘
                                       │ writes to
┌─────────────────── GPU / Shaders ────────────────────┐
│  PageTableUpdate.usf         update page table tex   │
│  VirtualTextureMaterial.ush  sample VT in materials  │
│  IndirectVirtualTexture.ush  adaptive VT indirection │
│  Feedback buffer             GPU→CPU page requests   │
└──────────────────────────────────────────────────────┘
```

## Per-Frame Lifecycle

```
1. GPU renders scene, material shaders sample VT, write feedback buffer
2. FVirtualTextureFeedback::TransferGPUToCPU() - async readback
3. FVirtualTextureSystem::Update()
   a. Map() feedback data → analyze visible pages
   b. Build FUniqueRequestList (deduplicated)
   c. For each request:
      - IVirtualTexture::RequestPageData() → status check
      - If Pending/Available: IVirtualTexture::ProducePageData()
        → returns IVirtualTextureFinalizer
   d. Execute Finalizer::RenderFinalize() (read pass)
   e. Execute Finalizer::Finalize() (write pass)
   f. PageTableUpdate.usf updates GPU page table textures
4. Evict unused tiles from physical pools (LRU)
```

## Key Design Patterns

1. **Producer-Consumer**: `IVirtualTexture` is the producer interface; `FVirtualTextureSystem` is the consumer. Clean separation allows different data sources (disk, procedural, material cache).

2. **Two-Phase Finalization**: Split GPU writes into read-only and write-only passes to avoid RW hazards on the physical texture pools.

3. **Shared Physical Spaces**: Multiple VTs share the same physical texture pool when they use compatible formats, reducing memory waste.

4. **Shared Page Table Spaces**: VTs with compatible layouts share a single `FVirtualTextureSpace`, enabling efficient page table texture usage.

5. **Feedback-Driven Residency**: GPU writes which pages are visible, CPU reads back and makes residency decisions — no CPU-side visibility calculation needed.

6. **Adaptive VT**: For runtime VTs, resolution per-UV-range is adjusted based on feedback without regenerating tiles, by remapping page table entries.






















Unreal Virtual Texture 系统架构分析
  
  系统总览

  VT 系统本质上是一个虚拟内存系统，将超大纹理拆分为固定大小的 Tile（页），按需加载到有限
  的物理纹理缓存中。核心抽象借鉴了操作系统的虚拟内存设计：虚拟地址空间 + 页表 +
  物理页池。

  ┌─────────────────────────────────────────────────────────┐
  │                    应用层 (Engine)                        │
  │  URuntimeVirtualTexture  UTexture2D (VT-enabled)        │
  └──────────┬──────────────────────────┬────────────────────┘
             │ 注册 Producer             │ 分配 AllocatedVT
  ┌──────────▼──────────────────────────▼────────────────────┐
  │              FVirtualTextureSystem (单例协调器)            │
  │  Update管线: Feedback → Gather → Produce → Finalize      │
  └────┬───────────┬───────────────────┬─────────────────────┘
       │           │                   │
  ┌────▼───┐  ┌────▼─────────┐  ┌─────▼──────────┐
  │Space[] │  │Producer[]    │  │PhysicalSpace[] │
  │虚拟地址 │  │数据生产者     │  │物理纹理池       │
  │+ 页表   │  │              │  │+ PagePool      │
  └────────┘  └──────────────┘  └────────────────┘

  ---
  Layer 1: 核心抽象 (RenderCore/Public/VirtualTexturing.h)
  
  此层定义了 VT 系统的所有公共接口，位于 RenderCore 模块，可被 Renderer 和 Engine
  模块共同引用。

  IVirtualTexture — 数据生产者接口

  - 核心方法: RequestPageData() 请求一页数据 → 返回状态
  (Invalid/Saturated/Pending/Available)
  - ProducePageData() 将数据写入目标 RenderTarget
  - GetLocalMipBias() 用于稀疏 VT 的 mip 偏移
  - 典型实现：磁盘流式加载 (SVT)、运行时渲染 (RVT)

  IAllocatedVirtualTexture — 已分配的虚拟纹理

  - 代表一段已分配的 VT 地址空间，拥有页表纹理和物理纹理引用
  - 关键属性：SpaceID（属于哪个 Space）、VirtualAddress（在 Space
  中的起始地址）、MaxLevel、NumTextureLayers
  - 提供 GetPageTableTexture() / GetPhysicalTexture() 供 shader 采样

  IVirtualTextureFinalizer — 最终写入器

  - RenderFinalize() — 只读访问物理池（RVT/材质系统需要采样其他 VT）
  - Finalize() — 写入物理纹理（不能采样）
  - 两阶段设计避免读写冲突

  IAdaptiveVirtualTexture — 自适应虚拟纹理

  - 管理多个 AllocatedVT 模拟更大的单一 VT
  - 用于 RuntimeVirtualTexture 的动态按需分配

  关键常量

  ┌────────────────────────────────────┬──────┬─────────────────────────────┐
  │                常量                │  值  │            含义             │
  ├────────────────────────────────────┼──────┼─────────────────────────────┤
  │ VIRTUALTEXTURE_SPACE_MAXLAYERS     │ 8    │ 单个页表最大层数            │
  ├────────────────────────────────────┼──────┼─────────────────────────────┤
  │ VIRTUALTEXTURE_MAX_PAGETABLE_SIZE  │ 4096 │ 页表纹理最大尺寸            │
  ├────────────────────────────────────┼──────┼─────────────────────────────┤
  │ VIRTUALTEXTURE_MAX_FEEDBACK_SPACES │ 16   │ 支持 Feedback 的 Space 数量 │
  └────────────────────────────────────┴──────┴─────────────────────────────┘

  ---
  Layer 2: 中央协调器 (Renderer/Private/VT/VirtualTextureSystem.h/.cpp)
  
  FVirtualTextureSystem 是全局单例（Initialize()/Get()），负责整个 VT
  的生命周期管理和帧更新管线。

  帧更新管线

  CallPendingCallbacks()     ← 在 UpdateAllPrimitiveSceneInfos 中调用
           ↓
  BeginUpdate()              ← 主要入口
    ├─ AllocateResources()
    ├─ AdaptiveVTs[].UpdateAllocations()  ← 自适应 VT 按需分配/释放
    ├─ DestroyPendingVirtualTextures()
    ├─ FlushDirtyRuntimeVirtualTextures() ← RVT 脏区域刷新
    └─ FVirtualTextureUpdater 创建
           ↓
  WaitForTasks()             ← 等待异步任务
           ↓
  EndUpdate()
    ├─ Feedback 分析 (GPU→CPU)
    ├─ Gather 请求 → 合并去重
    ├─ Produce 页数据 → Producer.ProducePageData()
    └─ Finalize → Finalizer.RenderFinalize() + Finalize()
           ↓
  FinalizeRequests()         ← 最终页表更新

  FVirtualTextureUpdater — 单帧更新上下文

  - 持有 FVirtualTextureUpdateSettings（节流参数：MaxRVTPageUploads / MaxSVTPageUploads
  / MaxPagesProduced）
  - 持有合并后的请求列表 MergedRequestList
  - 持有 Feedback 映射结果 FeedbackMapResult
  - 可选异步执行 (bAsyncTaskAllowed)

  关键管理集合

  - AllocatedVTs[] — 所有已分配的 VT
  - AdaptiveVTs[] — 所有自适应 VT
  - PhysicalSpaces[] — 所有物理空间
  - Spaces[] — 所有虚拟地址空间
  - Producers (FVirtualTextureProducerCollection) — Producer 注册表

  ---
  Layer 3: 虚拟内存管理 (VirtualTextureSpace.h, TexturePageMap.h)
  
  FVirtualTextureSpace — 虚拟地址空间

  - 继承自 FRenderResource，代表一个由页表纹理映射的虚拟地址空间
  - 核心数据结构:
    - PageTable[TextureCapacity] — 页表纹理（每张 4 层，UInt16 或 UInt32 格式）
    - PageTableIndirection — 间接纹理（用于 AdaptiveVT 寻址）
    - FVirtualTextureAllocator Allocator — 虚拟地址分配器（管理 vAddress 分配/释放）
    - FTexturePageMap PhysicalPageMap[Layers] — 每层的物理页映射
  - 同类型共享: 多个相同配置的 AllocatedVT 共享同一个 Space（除非 bPrivateSpace）
  - 页表更新: QueueUpdate() / ApplyUpdates() 批量更新页表纹理

  FTexturePageMap — 物理页映射

  - 跟踪虚拟地址到物理页位置的映射关系
  - 用于查找最近的可用 mip 级别

  ---
  Layer 4: 物理存储 (VirtualTexturePhysicalSpace.h, TexturePagePool.h)
  
  FVirtualTexturePhysicalSpace — 物理纹理空间

  - 继承自 FRenderResource，持有实际的物理纹理（GPU 显存）
  - 关键属性：TileSize、SizeInTiles（如 128×128 tiles）、Format[]（多层格式）
  - 每个 PhysicalSpace 关联一个 FTexturePagePool

  FTexturePagePool — 物理页池（核心缓存管理）

  - LRU 驱逐策略: 使用 FBinaryHeap 实现 LRU 堆，按帧使用时间排序
  - 关键操作:
    - Alloc() — 分配物理页，池满时 LRU 驱逐最久未用的页
    - Free() — 释放物理页
    - Lock() / Unlock() — 锁定页防止驱逐（用于常驻 mip）
    - MapPage() — 将物理页映射到虚拟地址空间的页表中
    - EvictPages() — 按 Producer/区域驱逐页
  - 多映射支持: 一个物理页可映射到多个虚拟地址（PageMapping[] 链表）

  ---
  Layer 5: 数据生产者 (VirtualTextureProducer.h, AdaptiveVirtualTexture.h)
  
  FVirtualTextureProducer — Producer 包装

  - 持有 IVirtualTexture* 实例和 FVTProducerDescription（尺寸、格式、层数）
  - 管理 PhysicalGroup：同一组内的层共享物理纹理和页表通道
  - 支持 LockedMipCount：锁定低 mip 层常驻

  FVirtualTextureProducerCollection — Producer 注册表

  - 使用 Handle（Index+Magic）管理 Producer 生命周期
  - 支持销毁回调（FVTProducerDestroyedFunction）
  - 链表式空闲管理

  两种 Producer 模式

  模式: SVT (Streaming VT)
  类: UTexture2D 的 VT 实现
  行为: RequestPageData() 返回 Pending，从磁盘异步加载
  ────────────────────────────────────────
  模式: RVT (Runtime VT)
  类: URuntimeVirtualTexture
  行为: RequestPageData() 返回 Available，ProducePageData() 实时渲染
  
  FAdaptiveVirtualTexture — 自适应 VT

  - 网格化分配：将大 VT 划分为 GridSize 的网格，每格可独立分配 AllocatedVT
  - AllocatedVirtualTextureLowMips — 持久低 mip 层
  - AllocationSlots[] + LRUHeap — 动态分配/驱逐高 mip 子区域
  - UpdateAllocations() — 根据 Feedback 请求按需增长/收缩

  ---
  Feedback 系统 (VirtualTextureFeedbackResource.h/.cpp)
  
  GPU 端记录所需的页请求 → 回读到 CPU → 驱动页加载。

  1. GPU 写入: 渲染时 shader 将所需的 (vAddress, vLevel) 写入 Feedback 缓冲区
  2. GPU 压缩: FVirtualTextureFeedbackBufferResource::End() 在 GPU 上去重压缩
  3. CPU 回读: 映射压缩后的缓冲区，分析页请求
  4. 请求合并: FUniqueRequestList 合并相同页的多次请求

  ---
  数据流总结
  
  渲染 Pass → GPU Feedback Buffer
                    ↓ (回读)
            FVirtualTextureSystem.BeginUpdate()
                    ↓
            FeedbackMapResult → 分析页需求
                    ↓
            GatherRequests → 合并去重 → MergedRequestList
                    ↓
            Producer.RequestPageData() → 请求页数据
                    ↓
            Producer.ProducePageData() → 生成页数据 → 写入 PhysicalSpace
                    ↓
            Finalizer.RenderFinalize() → 读阶段（VT 采样 VT）
            Finalizer.Finalize()       → 写阶段（提交到物理纹理）
                    ↓
            Space.ApplyUpdates() → 更新页表纹理
                    ↓
            下一帧渲染时 shader 通过页表采样到新数据