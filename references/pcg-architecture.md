# PCG (Procedural Content Generation) System Architecture

## Overview

PCG adopts a **Directed Acyclic Graph (DAG) execution model**:

```
UPCGComponent (trigger) → UPCGSubsystem (dispatch) → FPCGGraphExecutor (execute)
  → FPCGGraphCompiler (compile) → FPCGGraphTask[] (task DAG)
  → IPCGElement (node execution) → FPCGDataCollection (data flow)
```

Module location: `Engine/Plugins/PCG/Source/PCG/`

---

## Core Layers and Class Structure

### 1. Asset Layer

| Class | File | Responsibility |
|---|---|---|
| `UPCGGraph` | `Public/PCGGraph.h` | PCG graph asset, extends `UPCGGraphInterface`, contains nodes, edges, parameters |
| `UPCGNode` | `Public/PCGNode.h` | Graph node, holds `UPCGSettings`, associated with `IPCGElement` |
| `UPCGComponent` | `Public/PCGComponent.h` | Scene component, extends `UActorComponent`, implements `IPCGGraphExecutionSource`, entry point for PCG generation |
| `UPCGGraphInstance` | — | Graph instance with parameter overrides (`FPCGOverrideInstancedPropertyBag`) |

### 2. Subsystem Layer

| Class | File | Responsibility |
|---|---|---|
| `UPCGSubsystem` | `Public/Subsystems/PCGSubsystem.h` | World subsystem (`UTickableWorldSubsystem`), manages all PCG execution, component mapping, GC |
| `IPCGGraphExecutionSource` | `Public/PCGGraphExecutionStateInterface.h` | Execution source interface: `GetGraph()`, `GetSeed()`, `GetTransform()`, `GetWorld()` |
| `IPCGGraphExecutionState` | Same file | Execution state interface: data, seed, transform, bounds queries |

`UPCGSubsystem` owns the `FPCGGraphExecutor` instance and manages the full lifecycle.

### 3. Compilation Layer

| Class | File | Responsibility |
|---|---|---|
| `FPCGGraphCompiler` | `Private/Graph/PCGGraphCompiler.h` | Compiles `UPCGGraph` → `FPCGGraphTask[]` task DAG |
| `FPCGGraphCompilerCache` | Same file | Compilation cache: `GraphToTaskMap`, `GraphToStackContextMap`, per-GridSize optimization |
| `FPCGGraphTask` | `Private/Graph/PCGGraphTask.h` | Compiled task unit with Element, I/O Pin connections, task dependencies |

```cpp
// Task input structure - describes inter-task data passing
struct FPCGGraphTaskInput {
    uint64 TaskId;
    TOptional<FPCGPinProperties> UpstreamPin;
    TOptional<FPCGPinProperties> DownstreamPin;
    bool bProvideData;
};

// Element source types
enum class EPCGElementSource {
    Trivial,             // Shared Trivial Element
    TrivialPostGraph,    // Post-graph Element
    Gather,              // Gather Element
    FromNode,            // Created from node Settings
    FromCookedSettings,  // Created from cooked Settings
};
```

### 4. Execution Layer

| Class | File | Responsibility |
|---|---|---|
| `FPCGGraphExecutor` | `Private/Graph/PCGGraphExecutor.h` | Core **executor**, extends `FGCObject`, manages task scheduling, multithreaded execution |
| `FPCGContext` | `Public/PCGContext.h` | Execution context, spans entire lifecycle of a single Element |

```cpp
class FPCGGraphExecutor : public FGCObject, public TSharedFromThis<FPCGGraphExecutor> {
    void Compile(UPCGGraph* InGraph);                        // Compile graph (threadsafe)
    FPCGTaskId Schedule(IPCGGraphExecutionSource*, ...);     // Schedule execution
    FPCGTaskId ScheduleGraph(FPCGScheduleGraphParams&);      // Schedule graph execution
    TArray<...> Cancel(IPCGGraphExecutionSource*);           // Cancel execution
};
```

**Execution phases** (`EPCGExecutionPhase`):

```
NotExecuted → PrepareData → Execute → PostExecute → Done
```

- **PrepareData**: Input preparation, suitable for multithreading
- **Execute**: Core logic, returns `false` if incomplete (resumes next frame)
- **PostExecute**: One-time cleanup

**Time-slicing**: `CVarTimePerFrame` controls per-frame PCG budget, enabling **cross-frame async execution**.

### 5. Element Layer

| Class | File | Responsibility |
|---|---|---|
| `IPCGElement` | `Public/PCGElement.h` | Core **interface** for node processing, all PCG node logic implements this |
| `FPCGElementPtr` | Same file | `TSharedPtr<IPCGElement, ESPMode::ThreadSafe>` |
| `UPCGSettings` | `Public/PCGSettings.h` | Node configuration, one per node |

```cpp
class IPCGElement {
protected:
    virtual bool PrepareDataInternal(FPCGContext*) const;   // Data preparation
    virtual bool ExecuteInternal(FPCGContext*) const = 0;   // Core execution (pure virtual)
    virtual void PostExecuteInternal(FPCGContext*) const;   // Post-processing
    virtual void AbortInternal(FPCGContext*) const;         // Cancellation

    virtual bool IsCancellable() const;                     // Can be cancelled
    virtual bool IsPassthrough(const UPCGSettings*) const;  // Optimization bypass
};
```

Built-in Elements (`Public/Elements/`):
- `PCGWorldQuery` — World spatial queries
- `PCGPointOperationElementBase` — Point operation base class
- `PCGGetDataInfo` — Data info retrieval
- `PCGConvertToAttributeSet` — Attribute conversion
- `PCGExecuteBlueprint` — Blueprint execution
- `PCGUnionElement` — Merge operation

### 6. Data Layer

**Data inheritance hierarchy**:

```
UObject
 └─ UPCGData                          // Data base (Public/PCGData.h)
     ├─ UPCGSpatialData               // Spatial data base (Public/Data/PCGSpatialData.h)
     │   ├─ UPCGBasePointData         // Base point data
     │   │   └─ UPCGPointData         // Point cloud data (Public/Data/PCGPointData.h)
     │   ├─ UPCGSurfaceData           // Surface data
     │   └─ UPCGSplineData            // Spline data
     ├─ UPCGMetadata                  // Metadata
     ├─ UPCGSettings                  // Settings data
     └─ UPCGToolData                  // Tool data
```

**Core data flow structures**:

```cpp
// Tagged data (data + pin label + tags)
struct FPCGTaggedData {
    TObjectPtr<UPCGData> Data;
    FName Pin;
    TSet<FString> Tags;
    bool bIsUsedMultipleTimes;  // Optimization hint
};

// Data collection — inter-node data carrier
struct FPCGDataCollection {
    TArray<FPCGTaggedData> TaggedData;
    TArray<FPCGTaggedData> Settings;

    TArray<FPCGTaggedData> GetAllInputs() const;
    TArray<FPCGTaggedData> GetInputsByPin(FName) const;
    TArray<FPCGTaggedData> GetSpatialInputsByPin(FName) const;
};
```

**Design philosophy**: Any concrete spatial data can **decay into point data** (with transform + metadata) — the "basic currency" of the PCG framework.

---

## Full Execution Flow

```
1. Trigger:    UPCGComponent::Generate()
2. Dispatch:   UPCGSubsystem → FPCGGraphExecutor::Schedule()
3. Compile:    FPCGGraphCompiler::Compile(UPCGGraph)
               → Output FPCGGraphTask[] (topologically sorted task DAG)
4. Execute loop (per-frame, time-budget limited):
   For each ready FPCGGraphTask:
     a. Collect upstream FPCGDataCollection
     b. Create/reuse FPCGContext
     c. IPCGElement::PrepareData (multithreadable)
     d. IPCGElement::ExecuteInternal (core logic)
     e. Returns false → resume next frame
     f. Returns true → PostExecute, output to downstream
5. Complete:   Output data → UPCGComponent
               → Generate ISM/Billboard scene resources
```

---

## Key Design Patterns

| Pattern | Application |
|---------|-------------|
| **DAG execution** | Graph compiled to topologically sorted task DAG, parallel scheduling for independent tasks |
| **Strategy pattern** | `IPCGElement` interface + `ExecuteInternal` pure virtual |
| **Coroutine-style execution** | Element returns `false` to pause, executor resumes next frame |
| **Data pipeline** | `FPCGDataCollection` flows between tasks, Pin connections define data routing |
| **Compile-Cache-Execute** | Graph compiled once, cached, runtime executes by task DAG |
| **Observer/Delegate** | `FOnPCGGraphGenerated` etc. for generation completion notification |
| **GC integration** | `FPCGGraphExecutor` extends `FGCObject`, proper UObject lifetime management |

---

## Key Design Features

### Async Frame-sliced Execution
`CVarTimePerFrame` controls per-frame time budget. Element `ExecuteInternal` returning `false` pauses execution until next frame — **never blocks the game thread**.

### Task DAG Multithreading
`CVarGraphMultithreading` enables parallel execution. PrepareData phase is naturally parallelizable (no side effects). Execute phase uses task dependencies for ordering.

### Compilation Cache & Incremental Updates
`FPCGGraphCompilerCache` caches compiled results per `UPCGGraph*`:
- Per-GridSize independent compilation for hierarchical generation
- Compute Graph (GPU compute) caching
- Auto-invalidation and recompilation in editor

### Subgraph Support
`UPCGSubgraphSettings` (`Public/PCGSubgraph.h`) enables graph nesting. `FPCGStackContext` tracks the call stack through subgraph levels.

### Hierarchical Generation
World Partition integration via `APCGPartitionActor` (`Public/Grid/PCGPartitionActor.h`) — scheduling execution per Grid Size block.

### Compute Graph (GPU Acceleration)
Integration with Compute Framework:
- `UPCGComputeGraph` — GPU compute graph
- `UPCGComputeKernel` — GPU compute kernel
- Compiler generates Compute Graphs in editor, runtime dispatches to GPU

---

## Directory Structure

```
Engine/Plugins/PCG/Source/PCG/
├── Public/
│   ├── PCGGraph.h              # UPCGGraph (graph asset)
│   ├── PCGNode.h               # UPCGNode (node)
│   ├── PCGComponent.h          # UPCGComponent (scene component)
│   ├── PCGElement.h            # IPCGElement (execution interface)
│   ├── PCGSettings.h           # UPCGSettings (configuration)
│   ├── PCGData.h               # UPCGData, FPCGDataCollection
│   ├── PCGContext.h            # FPCGContext (execution context)
│   ├── PCGPin.h                # UPCGPin (connection pins)
│   ├── PCGSubgraph.h           # Subgraph support
│   ├── Data/
│   │   ├── PCGSpatialData.h    # UPCGSpatialData
│   │   ├── PCGPointData.h      # UPCGPointData
│   │   └── PCGMetadata.h       # Metadata
│   ├── Elements/               # Built-in node Element implementations
│   │   ├── PCGWorldQuery.h
│   │   ├── PCGPointOperationElementBase.h
│   │   ├── PCGExecuteBlueprint.h
│   │   └── ...
│   ├── Subsystems/
│   │   └── PCGSubsystem.h      # UPCGSubsystem
│   └── Grid/
│       └── PCGPartitionActor.h # Partition Actor
└── Private/
    ├── Graph/
    │   ├── PCGGraphExecutor.h/cpp  # FPCGGraphExecutor (core executor)
    │   ├── PCGGraphCompiler.h      # FPCGGraphCompiler (compiler)
    │   ├── PCGGraphTask.h          # FPCGGraphTask (task unit)
    │   └── PCGGraphCache.h         # Execution cache
    └── Compute/                    # GPU compute support
        └── Elements/
```

---

## Search Efficiency Notes

- **Expanded terms for PCG searches**: `["UPCGGraph", "UPCGComponent", "UPCGNode", "UPCGElement", "FPCGGraphExecutor", "FPCGData", "FPCGPointData", "FPCGMetadata", "UPCGSettings", "IPCGElement", "ProceduralContentGeneration"]`
- **Module filter**: Always use `module="PCG"` to narrow results
- **Key files are split across Public/ and Private/Graph/**: executor and compiler are in Private, interfaces in Public
- **`UPCGComponent` anchor**: Use `class UPCGComponent : public UActorComponent` (not `USceneComponent`)
- **Data classes**: `UPCGSpatialData` is in `Public/Data/PCGSpatialData.h`, not directly in `Public/`
