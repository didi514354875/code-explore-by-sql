# UE Landscape 地形系统架构与设计思路分析

## 一、整体架构概览

```
┌─────────────────────────────────────────────────────────┐
│                    Game Thread                          │
│  ALandscape ──owns──> ULandscapeInfo (数据枢纽)         │
│       │                                                 │
│       ├── ALandscapeStreamingProxy (World Partition)    │
│       │       │                                         │
│       │       ├── ULandscapeComponent[] (渲染组件)       │
│       │       │     ├── HeightmapTexture (高度图)        │
│       │       │     ├── WeightmapTextures[] (权重图)     │
│       │       │     └── GrassTypes[] (草地类型)          │
│       │       │                                         │
│       │       ├── ULandscapeHeightfieldCollisionComponent│
│       │       │     └── Chaos::FHeightField (碰撞)      │
│       │       │                                         │
│       │       └── ULandscapeNaniteComponent (Nanite渲染) │
│       │                                                 │
│       └── ULandscapeSplinesComponent (样条线)           │
└─────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌──────────────────┐ ┌──────────────────┐
│  Render Thread   │ │  Editing System  │
│  SceneProxy      │ │  FLEDI           │
│  Material (LOD)  │ │  Edit Layers     │
└──────────────────┘ └──────────────────┘
```

## 二、Actor 层次结构（Layer 1: Core Actors）

继承链：

```
AActor
  └── APartitionActor              ← World Partition 分区 Actor 基类
        └── ALandscapeProxy         ← 地形代理抽象基类 (Abstract, NotPlaceable)
              ├── ALandscape        ← 主地形 Actor（编辑入口、数据权威）
              └── ALandscapeStreamingProxy  ← 流式加载代理（World Partition 子分区）
```

**设计思路：**

1. **`ALandscapeProxy`** 是所有地形 Actor 的公共基类，继承自 `APartitionActor`（非普通的 `AActor`），这决定了地形系统原生支持 **World Partition** 的数据分层加载。

2. **`ALandscape`** 是唯一的"编辑权威"。它额外实现了 `IEditLayerRendererProvider` 接口（5.7+ 版本），承载 Edit Layer 系统。运行时通过 `GetLandscapeActor()` 返回自身。

3. **`ALandscapeStreamingProxy`** 是世界分区场景下的轻量代理，持有 `TSoftObjectPtr<ALandscape>` 引用其主 Actor。当大地图被切割为多个分区时，每个分区生成一个 StreamingProxy，仅加载必要部分。关键设计：`ShouldExport() { return false; }` — 流式代理不导出，属于运行时派生。

4. **`LandscapeGuid`** 贯穿所有 Proxy，确保同一逻辑地形即使被分区切割也能被识别为同一实体。成员标记 `meta = (LandscapeInherited)` 表示此属性由 ALandscape 统一下发到所有 StreamingProxy。

### 核心源文件

| 类 | 头文件 |
|----|--------|
| ALandscapeProxy | `Engine/Source/Runtime/Landscape/Classes/LandscapeProxy.h` |
| ALandscape | `Engine/Source/Runtime/Landscape/Classes/Landscape.h` |
| ALandscapeStreamingProxy | `Engine/Source/Runtime/Landscape/Classes/LandscapeStreamingProxy.h` |

## 三、组件层（Layer 2: Component Layer）

### ULandscapeComponent — 渲染单元

```
UPrimitiveComponent
  └── ULandscapeComponent        (Within=LandscapeProxy，只能挂在 LandscapeProxy 下)
```

**核心网格参数：**
- `SectionBaseX/Y` — 全局组件网格偏移（以四边形为单位）
- `ComponentSizeQuads` — 组件四边形总数
- `SubsectionSizeQuads` — 子分段大小（+1 必须是 2 的幂）
- `NumSubsections` — X/Y 方向子分段数

**纹理数据绑定：**
- `HeightmapTexture` — 高度图 (UTexture2D)，通过 `HeightmapScaleBias` UV 偏移定位
- `WeightmapTextures[]` — 多个权重图纹理，每个纹理最多 4 通道（RGBA = 4 层材质权重）
- `WeightmapLayerAllocations[]` — 记录每层权重存储在哪个纹理的哪个通道

**材质系统：**
- `MaterialInstances[]` — 按 LOD 索引的材质实例数组，LOD 到材质的映射由 `LODIndexToMaterialIndex[]` 维护
- `OverrideMaterial` / `OverrideHoleMaterial` — 逐组件材质覆盖

**Edit Layer 数据存储：**
- `LayersData: TMap<FGuid, FLandscapeLayerComponentData>` — 按 Edit Layer GUID 索引的编辑层数据
- `ObsoleteEditLayerData` — 已废弃编辑层的暂存

### ULandscapeHeightfieldCollisionComponent — 碰撞单元

```
UPrimitiveComponent
  └── ULandscapeHeightfieldCollisionComponent    (Within=LandscapeProxy)
```

- 与 ULandscapeComponent **1:1 对应**，独立管理碰撞和物理查询
- 底层使用 `Chaos::FHeightField` 实现物理引擎高度场碰撞
- 同时承载物理材质（Physical Material）信息

### ULandscapeNaniteComponent — Nanite 渲染

```
UStaticMeshComponent
  └── ULandscapeNaniteComponent    (Within=LandscapeProxy)
```

- **继承自 `UStaticMeshComponent` 而非 UPrimitiveComponent** — 关键设计决策！Nanite 地形本质上被当作"静态网格"渲染，复用 Nanite 的 LOD 和裁剪管线
- 通过 `bEnableNanite` 在 ALandscapeProxy 上启用

### 核心源文件

| 类 | 头文件 |
|----|--------|
| ULandscapeComponent | `Engine/Source/Runtime/Landscape/Classes/LandscapeComponent.h` |
| ULandscapeHeightfieldCollisionComponent | `Engine/Source/Runtime/Landscape/Classes/LandscapeHeightfieldCollisionComponent.h` |
| ULandscapeNaniteComponent | `Engine/Source/Runtime/Landscape/Classes/LandscapeNaniteComponent.h` |

## 四、数据模型（Layer 3: Data Model）

### 数据存储方式：纹理即数据

地形系统的核心设计哲学是 **"Texture as Data"** — 高度、权重、选择状态全部存储在 `UTexture2D` 中：

| 数据类型 | 纹理格式 | 说明 |
|---------|---------|------|
| Heightmap | R16 (uint16) | 高度值存储在 R 通道，G 通道存法线或标记 |
| Weightmap | R8 (uint8 per channel) | 每通道一个材质层权重，一张纹理最多 4 层 |
| XYOffset | (deprecated 5.7) | 顶点 XY 偏移，已随 Edit Layer 统一废弃 |

**Mip-to-Mip Delta 系统：**

`MipToMipMaxDeltas` 存储相邻 LOD 之间的最大顶点偏移量。这个数据用于：
1. LOD 切换时的屏幕空间误差 (SSE) 估算
2. LOD Blend Range 的缝合控制

数组布局：对于 5 个相关 Mip，按 `[0→1], [0→2], [0→3], [1→2], [1→3], [2→3]` 顺序存储。

### ULandscapeInfo — 全局数据枢纽

```
UObject
  └── ULandscapeInfo     (Transient)
```

**关键数据结构：**
- `XYtoComponentMap: TMap<FIntPoint, ULandscapeComponent*>` — 全局组件坐标 → 渲染组件查找表
- `XYtoCollisionComponentMap` — 全局组件坐标 → 碰撞组件查找表
- `Layers[]: TArray<FLandscapeInfoLayerSettings>` — 材质层元信息（LayerInfoObj + LayerName）
- `LandscapeActor: TWeakObjectPtr<ALandscape>` — 反向引用主 ALandscape
- `LandscapeGuid: FGuid` — 唯一标识符，贯穿所有 Proxy
- `ComponentSizeQuads / SubsectionSizeQuads / ComponentNumSubsections` — 网格参数
- `SelectedComponents` / `SelectedRegion` — 编辑器选区管理

ULandscapeInfo 是一个 **单例模式**（每个 LandscapeGuid 一个），所有 Proxy 共享同一个 Info 实例，充当数据协调中心。

### Edit Layer 混合系统 — UE5 非破坏编辑核心

`LandscapeEditLayerTypes.h` 定义了 Heightmap/Weightmap 的 GPU 混合模式：

**Heightmap 混合模式（EHeightmapBlendMode）：**
| 模式 | 说明 |
|------|------|
| `Additive` | 高度偏移（正负均可） |
| `LegacyAlphaBlend` | 预乘 Alpha（旧版样条线兼容） |
| `AlphaBlend` | 标准 Alpha 混合 |

**Weightmap 混合模式（EWeightmapBlendMode）：**
| 模式 | 说明 |
|------|------|
| `Additive` | 权重偏移（正向） |
| `Subtractive` | 权重偏移（负向） |
| `Passthrough` | 不混合，直接传递 |
| `AlphaBlend` | 完全 Alpha 混合 |

**混合参数结构：**
```c++
struct FBlendParams {
    FHeightmapBlendParams HeightmapBlendParams;          // {BlendMode, Alpha}
    TMap<FName, FWeightmapBlendParams> WeightmapBlendParams;  // 按层名索引
};
```

GPU 着色器实现：`LandscapeEditLayersHeightmaps.usf`（高度混合）/ `LandscapeEditLayersWeightmaps.usf`（权重混合）。

**ULandscapeEditLayerBase** — 编辑层基类（可扩展）：
- 声明支持能力：支持雕刻？绘画？可折叠？可分组渲染？
- 实现 `IEditLayerRendererProvider` 接口
- `ERenderFlags`：`RenderMode_Recorded`（录制到 FRDGBuilder）/ `RenderMode_Immediate`（立即执行）/ `BlendMode_SeparateBlend`（分离渲染和混合）/ `RenderLayerGroup_SupportsGrouping`（支持层组批量渲染）

### FLandscapeEditDataInterface — 编辑通道

```
struct FLandscapeEditDataInterface   (LandscapeEdit.h)
```

这是地形编辑的核心 API，提供：
- **Heightmap 读写**：`SetHeightData` / `GetHeightData`（支持逐点、区域、稀疏数据）
- **Weightmap 读写**：`SetAlphaData` / `GetWeightData`（按 LayerInfo 索引）
- **Edit Layer 切换**：`SetEditLayer(FGuid)` — 支持多层非破坏编辑
- **数据缺失插值**：`CalcMissingValues` — 处理部分加载时的边界补全
- **辅助数据**：`GetSelectData` / `GetLayerContributionData` / `GetDirtyData`

构造时绑定 `ULandscapeInfo*` 和可选的 Edit Layer GUID，实现 **按层隔离的编辑操作**。

核心源文件：`Engine/Source/Runtime/Landscape/Public/LandscapeEdit.h`

## 五、渲染系统（Layer 4: Rendering）

### 5.1 LOD 渲染架构

```
FLandscapeSceneViewExtension : FSceneViewExtensionBase   ← 视图扩展，驱动每帧 LOD 计算
  └── FLandscapeRenderSystem[]                           ← 每 Landscape 一个（按 LandscapeKey 索引）
        ├── SectionInfos[]                               ← 2D 网格索引的 Section 列表
        ├── SectionLODBiases: TResourceArray<float>      ← GPU Buffer：每 Section 的 LOD 偏移
        ├── PerViewCachedSectionLODValues                 ← 每视图缓存 LOD 值
        ├── SectionLODBiasBuffer → SectionLODBiasSRV     ← GPU SRV，着色器直接读取
        └── ComputeSectionsLODForView()                  ← 基于屏幕空间面积计算 LOD
```

**FLandscapeSectionInfo** — LOD 计算的最小单元（虚基类）：
- `RenderCoord` — 在 RenderSystem 2D 网格中的坐标
- `ComponentBase` — 相对于 ALandscape 的偏移
- `ComputeLODForView()` — 纯虚函数，由派生类实现具体 LOD 策略
- `ComputeSectionResolution()` — 世界空间每顶点分辨率

**FLandscapeComponentSceneProxy** 同时继承 `FPrimitiveSceneProxy` + `FLandscapeSectionInfo`，是渲染端核心：
- LOD 值通过 `ComputeLODFromScreenSize()` 基于屏幕空间面积计算
- 写入 GPU Uniform Buffer（`SectionLODUniformBuffer`），顶点着色器直接采样
- 支持阴影缓存失效检测（VSM 场景下的 `ShouldInvalidateShadows`）

### 5.2 顶点工厂管线（VTF — Vertex Texture Fetch）

```
FLandscapeVertexFactory : FVertexFactory          ← 基础 VTF 高度图顶点工厂
  └── FLandscapeFixedGridVertexFactory            ← 固定网格 VT LOD 变体
FLandscapeXYOffsetVertexFactory (deprecated 5.7)  ← XY 偏移变体，随 Edit Layer 统一废弃
```

**核心设计 — 极简顶点：**

```c++
struct FLandscapeVertex {
    uint8 VertexX, VertexY;   // 组件内网格坐标
    uint8 SubX, SubY;         // 子段内坐标
};  // 仅 4 字节/顶点！
```

所有高度信息存储在 HeightmapTexture 中，由着色器采样（VTF 技术）。这意味着：
- CPU 端几乎零开销（无顶点动画计算）
- LOD 切换 = 切换纹理 Mip 级别 + 简化索引缓冲
- 百万级顶点的地形在 CPU 侧几乎"免费"

**FLandscapeSharedBuffers** — 引用计数的共享缓冲池：
- 按 `(ComponentSizeQuads, NumSubsections)` 组合复用
- 包含：VertexBuffer、IndexBuffer（每 mip 一个）、VertexFactory、GrassIndexBuffer
- `SharedBuffersMap` 全局静态缓存，相同尺寸的组件共享同一套缓冲

### 5.3 LOD 配置

| 参数 | 作用 |
|------|------|
| `MaxLODLevel` | 最大 LOD 级别 |
| `LOD0ScreenSize` | LOD0 屏幕尺寸阈值 |
| `LOD0DistributionSetting` | LOD0 分布密度（默认 1.25） |
| `LODDistributionSetting` | 其余 LOD 分布密度（默认 3.0） |
| `LODBlendRange` | LOD 过渡混合区域（0.01-1.0） |
| `LODGroupKey` | LOD 组，同组地形同步 LOD 消除接缝 |
| `ScalableLOD*` | 可扩展质量级别版本 |

**LOD 渲染路径：**
1. **传统路径**：`ULandscapeComponent` → `FLandscapeComponentSceneProxy`，按屏幕大小切换 LOD，顶点着色器采样 Heightmap Mip
2. **Nanite 路径**：`ULandscapeNaniteComponent` 将地形转为静态网格，复用 Nanite 微多边形管线

**LODGroupKey 设计** — 同一 LOD 组内的地形共享 `FLandscapeRenderSystem`，同步 LOD 决策，消除分区接缝裂缝。RenderSystem 还验证组内所有地形的 `ComponentResolution`/`ComponentOrigin`/`ComponentXVector`/`ComponentYVector` 一致性。

### 5.4 Nanite 集成

```
ULandscapeNaniteComponent : UStaticMeshComponent    (Within=LandscapeProxy)
```

- 继承自 `UStaticMeshComponent`（非 UPrimitiveComponent）— 复用 Nanite 的 LOD 和裁剪管线
- 异步管线生命周期：`FBuildTask` 跟踪时间戳 `LandscapeUpdateStart → StaticMeshBuildStart → StaticMeshBuildEnd → LandscapeUpdateEnd → Complete`
- Nanite 模式下不再使用 VTF+LOD 管线，利用 Nanite 自动 LOD
- 通过 `bEnableNanite` 在 ALandscapeProxy 上启用

## 六、Grass/Foliage 系统（Layer 6）

### 数据驱动的草地生成

架构链：

```
Material Graph
  └── UMaterialExpressionLandscapeGrassOutput (材质节点)
        └── FGrassInput[] → ULandscapeGrassType → FGrassVariety[]
              ↓
        ULandscapeComponent.GrassTypes[] (缓存)
              ↓
        FAsyncGrassTask (异步构建)
              ↓
        UHierarchicalInstancedStaticMeshComponent (HISM 渲染)
```

**设计思路：**

1. **材质驱动**：`UMaterialExpressionLandscapeGrassOutput` 是材质图中的一个 CustomOutput 节点，每个输入绑定一个 `ULandscapeGrassType`。材质编译时生成 `GetGrassWeight()` shader 函数，运行时渲染到 Grass Weight Map。

2. **ULandscapeGrassType** 是纯数据资产，包含 `FGrassVariety[]`（静态网格、密度、剔除距离等）。

3. **异步构建**：`FAsyncGrassTask` 在线程池中根据 Weight Map 计算实例位置，生成 HISMC 实例数据。

4. **两种模式**：
   - 烘焙模式：序列化 Grass Map 到磁盘（`bDisableRuntimeGrassMapGeneration = true`）
   - 运行时模式：加载时异步计算（默认）

5. **FCachedLandscapeFoliage** 在 ALandscapeProxy 上缓存运行时植被状态，按组件 x GrassType 索引。

### 核心源文件

| 类 | 头文件 |
|----|--------|
| ULandscapeGrassType | `Engine/Source/Runtime/Landscape/Classes/LandscapeGrassType.h` |
| UMaterialExpressionLandscapeGrassOutput | `Engine/Source/Runtime/Landscape/Classes/Materials/MaterialExpressionLandscapeGrassOutput.h` |
| FLandscapeGrassWeightExporter_RenderThread | `Engine/Source/Runtime/Landscape/Internal/LandscapeGrassWeightExporter.h` |

## 七、ULandscapeSubsystem — World 级管理器

```
UTickableWorldSubsystem
  └── ULandscapeSubsystem     (可编辑器 Tick, 336行)
```

- `RegisterActor(ALandscapeProxy*)` / `UnregisterActor` — 管理所有 Proxy 的注册/注销
- `RegisterComponent(ULandscapeComponent*)` / `UnregisterComponent` — 组件级注册（触发 Edge Fixup、Grass 更新）
- `Tick(float DeltaTime)` — 驱动草地创建/销毁循环、Edge Fixup 分摊处理
- `FOnHeightmapStreamedDelegate` — 高度图流式加载完成回调（含更新区域和涉及的组件集合）
- 支持 `DoesSupportWorldType` 过滤世界类型
- `PrioritizeGrassCreation()` — 提升草地生成优先级（乘以 GGrassCreationPrioritizedMultipler）
- `GetGrassMapBuilder()` — 返回 `FLandscapeGrassMapsBuilder` 实例
- `GetTextureStreamingManager()` — 返回 `FLandscapeTextureStreamingManager` 实例
- `RegenerateGrass()` — 运行时动态重新生成草（可指定相机位置）
- `RemoveGrassInstances()` — 按组件集合移除草实例

**编辑器构建接口（WITH_EDITOR）：**
- `BuildAll(EBuildFlags)` — 全量构建
- `BuildGrassMaps(EBuildFlags)` — 构建草地图
- `BuildPhysicalMaterial(EBuildFlags)` — 构建物理材质
- `BuildNanite(EBuildFlags, Proxies)` — 异步构建 Nanite 网格（支持增量检测）
- `GetOutdatedProxyDetails()` — 检测过时代理数据
- `MarkModifiedLandscapesAsDirty()` / `SaveModifiedLandscapes()` — 自动脏标记与保存
- `ChangeGridSize()` / `FindOrAddLandscapeProxy()` — 网格管理
- `OnLandscapeProxyComponentDataChanged` / `OnLandscapeProxyMaterialChanged` — 变更通知委托

核心源文件：`Engine/Source/Runtime/Landscape/Public/LandscapeSubsystem.h`

## 七-A、FLandscapeGroup — 高度图接缝修复系统

```
FLandscapeGroup (非UObject, 纯C++结构, LandscapeGroup.h:22-100)
```

**核心问题：** 相邻 Component 的高度图纹理在边缘处会出现接缝（因为每个 Component 独立管理自己的 HeightmapTexture Mip 链）。

**解决方案 — Edge Fixup 三阶段流水线：**

1. **坐标系映射** — `GroupCoordOrigin / GroupCoordXVector / GroupCoordYVector` 定义 Group 级统一坐标系，第一个注册的 Component 决定原点
2. **Edge Snapshot** — `ULandscapeHeightmapTextureEdgeFixup` 捕获每个 Component 的边缘像素快照
3. **GPU Edge Patching** — 在纹理流式加载时通过 `ULandscapeTextureMipEdgeOverrideFactory` 或 `ULandscapeTextureStorageProviderFactory` 修正边缘

**关键数据结构：**
- `XYToEdgeFixupMap: TMap<FIntPoint, ULandscapeHeightmapTextureEdgeFixup*>` — Group 坐标到修复对象映射
- `HeightmapsNeedingEdgeSnapshotCapture` — 需要重新捕获快照的集合
- `HeightmapsNeedingEdgeTexturePatching` — 需要 GPU 修补的集合
- `HeightmapsMoved` — 已移动可能需要重新映射的集合
- `RWLock` — 读写锁保护（渲染线程读取，游戏线程写入）
- `AmortizeIndex` — 分摊处理游标，避免单帧过多修补操作

**接口：**
- `RegisterComponent(Component)` — 注册组件到 Group，分配坐标
- `UnregisterComponent(Component)` — 注销组件
- `OnTransformUpdated(Component)` — Transform 变更时重新映射
- `TickEdgeFixup(LandscapeSubsystem, bForcePatchAll)` — 每帧分摊处理边缘修复
- `RegisterAllComponentsOnStreamingProxy(StreamingProxy)` — 批量注册

**高度图纹理共享检测：**
- `static HeightmapTextureToActiveComponent: TMap<UTexture2D, ULandscapeComponent>` — 全局映射，检测多个组件是否共享同一高度图纹理

核心源文件：`Engine/Source/Runtime/Landscape/Private/LandscapeGroup.h`

## 七-B、Edit Layer Merge Pipeline

**GPU 合并管线架构：**

```
ULandscapeEditLayerBase (编辑层抽象)
  ↓ 提供每层的高度图/权重图纹理
ALandscape.RenderMergedTextureInternal() (Landscape.cpp:3658-3954)
  ↓ 协调多层渲染目标合并
  ├── EHeightmapRTType — 高度图中间缓冲枚举
  │     HeightmapRT_CombinedAtlas / CombinedNonAtlas / Scratch1-3 / Mip1-7
  ├── EWeightmapRTType — 权重图中间缓冲枚举
  │     WeightmapRT_Scratch_RGBA / Scratch1-3 / Mip0-7
  └── GPU Shader 执行混合
        ├── LandscapeEditLayersHeightmaps.usf (高度混合)
        └── LandscapeEditLayersWeightmaps.usf (权重混合)
```

**`ULandscapeEditLayerBase` 关键虚接口（LandscapeEditLayer.h:46-378）：**

| 方法 | 用途 |
|------|------|
| `SupportsTargetType(InType)` | 是否支持 Heightmap/Weightmap/Visibility |
| `NeedsPersistentTextures()` | 是否需要分配纹理（纯程序化层返回 false） |
| `SupportsEditingTools()` | 是否支持手动雕刻/绘画 |
| `SupportsMultiple()` | 是否允许同时存在多个同类型层 |
| `SupportsBlueprintBrushes()` | 是否支持蓝图笔刷 |
| `SupportsBeingCollapsedAway()` | 是否支持被上层折叠 |
| `SupportsCollapsingTo()` | 是否支持折叠到下层 |
| `SupportsAlphaForTargetType(InType)` | 是否支持指定类型的 Alpha |
| `SetAlphaForTargetType / GetAlphaForTargetType` | 读写层 Alpha |

**Merge 流程（在 Render Thread）：**
1. 收集所有活跃 Edit Layer 的纹理和混合参数
2. 从底层到顶层依次渲染到中间 Render Target
3. 每层应用其 `BlendMode`（Additive/AlphaBlend/Passthrough）和 Alpha
4. 最终合成结果写回 Component 的 HeightmapTexture/WeightmapTextures
5. 触发碰撞更新和 Grass 重建

## 八、核心设计思路总结

| 设计原则 | 体现 |
|---------|------|
| **Texture as Data** | 高度/权重全存 UTexture2D，GPU 直接采样，CPU 通过 FLEDI 编辑 |
| **Partition-First** | 继承 APartitionActor，原生支持 World Partition 流式加载 |
| **GPU-Driven LOD** | FLandscapeRenderSystem 统一计算 LOD → GPU Buffer → 着色器直接读取，CPU 零开销 |
| **极简顶点（4B/vert）** | FLandscapeVertex 仅 4 字节，高度完全由 VTF 采样，百万顶点"免费"渲染 |
| **SharedBuffers 复用** | 相同尺寸组件共享 Vertex/Index Buffer，大幅降低内存占用 |
| **Edit Layer 非破坏编辑** | 5.7+ 统一 Edit Layer 系统，GPU 着色器执行混合（Additive/AlphaBlend/Passthrough） |
| **数据-渲染-碰撞 三分离** | ULandscapeInfo(数据) <-> ULandscapeComponent(渲染) <-> ULandscapeHeightfieldCollisionComponent(碰撞) |
| **Nanite 兼容** | 继承 UStaticMeshComponent 复用 Nanite 管线，传统路径保持兼容 |
| **Material-Driven Foliage** | 草地类型由材质图输出决定，密度由 shader 运行时计算 |
| **LOD Group 同步** | 同组地形共享 FLandscapeRenderSystem，同步 LOD 决策，消除分区接缝 |
| **属性继承体系** | `meta = (LandscapeInherited)` 标记共享属性，ALandscape 下发到所有 StreamingProxy |
| **Group-based Edge Fixup** | FLandscapeGroup 统一坐标系映射 + Edge Snapshot + GPU Patching 三阶段消除组件间接缝，分摊处理避免帧率卡顿 |
| **GPU Merge Pipeline** | Edit Layer 合并在 Render Thread 执行，多层 Render Target 中间缓冲，支持 Additive/AlphaBlend/Passthrough 混合 |
| **Subsystem 集中调度** | ULandscapeSubsystem 作为 World 级协调器统一管理注册/注销、Grass 生成、Nanite 构建、Edge Fixup 等异步任务 |
| **共享属性覆盖机制** | StreamingProxy 可独立覆盖主 Actor 的共享属性（`OverriddenSharedProperties`），灵活性与一致性兼顾 |

## 九、模块结构

所有核心代码位于 `Engine/Source/Runtime/Landscape/` 下：

```
Runtime/Landscape/
├── Classes/              ← 公共头文件（UHT 生成代码所需）
│   ├── Landscape.h               ALandscape
│   ├── LandscapeProxy.h          ALandscapeProxy
│   ├── LandscapeComponent.h      ULandscapeComponent
│   ├── LandscapeStreamingProxy.h ALandscapeStreamingProxy
│   ├── LandscapeInfo.h           ULandscapeInfo
│   ├── LandscapeHeightfieldCollisionComponent.h
│   ├── LandscapeNaniteComponent.h
│   ├── LandscapeGrassType.h
│   ├── Materials/
│   │   └── MaterialExpressionLandscapeGrassOutput.h
├── Public/
│   ├── LandscapeEdit.h           FLandscapeEditDataInterface
│   ├── LandscapeSubsystem.h      UE::Landscape 命名空间
│   └── LandscapeLight.h
├── Private/              ← 实现文件
│   ├── Landscape.cpp
│   ├── LandscapeComponent.cpp
│   ├── LandscapeEdit.cpp
│   ├── LandscapeProxy.cpp
│   ├── LandscapeSubsystem.cpp
│   └── ...
└── Internal/             ← 内部实现细节
    └── LandscapeGrassWeightExporter.h
```

编辑器扩展位于 `Engine/Source/Editor/LandscapeEditor/`。
