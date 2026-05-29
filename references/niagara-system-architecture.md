# UE Niagara System Architecture

Niagara particle/VFX system: four-layer design (Asset → Runtime Instance → Simulation → GPU Compute).
Analyzed via unreal-source-mcp with 37 tool calls (~26K tokens, 97% savings vs full-file reads).

## Core Class Hierarchy

```
                    ┌─── UFXSystemAsset ───┐
                    │                      │
             UNiagaraSystem          UNiagaraEmitterBase
                    │                      │
    (contains UNiagaraEmitter[])    UNiagaraEmitter
                    │                      │
            INiagaraParameterDefs   UNiagaraScript (execution graphs)
            Subscriber              ENiagaraScriptUsage

UNiagaraDataInterfaceBase
  └── UNiagaraDataInterface (20+ subclasses: Grid2D/3D, CurlNoise, VectorField, Audio, Curve, Array)

FNiagaraVariableBase (USTRUCT: Name + FNiagaraTypeDefinitionHandle)

UPrimitiveComponent
  └── UNiagaraComponent (runtime component for a Niagara System)
```

## Runtime Instance Hierarchy

```
FGCObject
  └── FNiagaraWorldManager          ← one per UWorld, owns all SystemSimulations
        └── FNiagaraSystemSimulation ← manages all instances of a system, async tick dispatch
              └── FNiagaraSystemInstance  ← runtime instance, holds emitter instances
                    ├── FNiagaraEmitterInstance (virtual base)
                    │     ├── FNiagaraEmitterInstanceImpl (stateful, final)
                    │     └── FNiagaraStatelessEmitterInstance
                    └── FNiagaraGpuComputeDispatchInterface ref
```

## Key File Locations

| Class | File | Directory |
|---|---|---|
| UNiagaraSystem | `Classes/NiagaraSystem.h` | Niagara module |
| UNiagaraEmitter | `Classes/NiagaraEmitter.h` | Niagara module |
| UNiagaraComponent | `Public/NiagaraComponent.h` | Niagara module |
| UNiagaraScript | `Classes/NiagaraScript.h` | Niagara module |
| UNiagaraDataInterface | `Classes/NiagaraDataInterface.h` | Niagara module |
| FNiagaraVariableBase | `Public/NiagaraTypes.h` | Niagara module |
| FNiagaraWorldManager | `Public/NiagaraWorldManager.h` | Niagara module |
| FNiagaraSystemSimulation | `Public/NiagaraSystemSimulation.h` | Niagara module |
| FNiagaraSystemInstance | `Public/NiagaraSystemInstance.h` | Niagara module |
| FNiagaraEmitterInstance | `Classes/NiagaraEmitterInstance.h` | Niagara module |
| FNiagaraEmitterInstanceImpl | `Internal/NiagaraEmitterInstanceImpl.h` | Niagara module |
| FNiagaraScriptExecutionContextBase | `Classes/NiagaraScriptExecutionContext.h` | Niagara module |
| FNiagaraComputeExecutionContext | `Classes/NiagaraComputeExecutionContext.h` | Niagara module |
| FNiagaraGpuComputeDispatchInterface | `Public/NiagaraGpuComputeDispatchInterface.h` | Niagara module |

**Directory convention**: Niagara headers split across `Classes/`, `Public/`, `Internal/` — always check all three.

## Simulation Pipeline (Async Tick Sequence)

From `NiagaraSystemSimulation.cpp` source comments:

### Tick Sequence
```
① NiagaraSystemSimulation::Tick_GameThread
   └─ Enqueue FNiagaraSystemSimulationTickConcurrentTask

② NiagaraSystemSimulation::Tick_Concurrent
   ├─ Enqueue FNiagaraSystemInstanceTickConcurrentTask (batch=4)
   ├─ Enqueue FNiagaraSystemInstanceFinalizeTask
   └─ Append to FNiagaraSystemSimulationAllWorkCompleteTask
```

### Spawn Sequence
```
① NiagaraSystemSimulation::Spawn_GameThread
   └─ Enqueue FNiagaraSystemSimulationSpawnConcurrentTask

② NiagaraSystemSimulation::Spawn_Concurrent
   ├─ Enqueue FNiagaraSystemInstanceTickConcurrentTask (waits for Spawn_Concurrent)
   ├─ Enqueue FNiagaraSystemInstanceFinalizeTask
   └─ Append to completion task
```

### GPU Tick Handling Modes (ENiagaraGPUTickHandlingMode)

| Mode | Description | Use Case |
|---|---|---|
| `None` | No GPU ticks | CPU-only simulation |
| `GameThread` | Individual submit on GT | Simple scenes |
| `Concurrent` | Individual submit during concurrent tick | Medium load |
| `GameThreadBatched` | Batched submit on GT | High load optimization |
| `ConcurrentBatched` | Batched submit during concurrent tick | Maximum throughput |

Batch size: `NiagaraSystemTickBatchSize = 4`

## GPU Compute Architecture

```
FNiagaraGpuComputeDispatchInterface (extends FFXSystemInterface)
    │
    ├── PreInitViews(RDGBuilder)
    │   └── GPUInstanceCounterManager.UpdateDrawIndirectBuffers(PreOpaque)
    ├── PostInitViews(RDGBuilder)
    ├── FNiagaraGPUSystemTick
    │   └── FNiagaraComputeExecutionContext[] per emitter
    │       ├── FNiagaraRHIUniformBufferLayout
    │       ├── FNiagaraGpuSpawnInfoParams
    │       └── FNiagaraGPUInstanceCountManager
    └── PostSystemTick_Concurrent
```

### GPU Dispatch Code Pattern
```cpp
// From NiagaraGpuComputeDispatch.cpp
FRDGBuilder GraphBuilder(RHICmdList);
CreateSystemTextures(GraphBuilder);
PreInitViews(GraphBuilder, bAllowGPUParticleUpdate, ...);
AddPass(GraphBuilder, "UpdateDrawIndirectBuffers - PreOpaque",
    [this](FRHICommandListImmediate& RHICmdList) {
        GPUInstanceCounterManager.UpdateDrawIndirectBuffers(
            this, RHICmdList, ENiagaraGPUCountUpdatePhase::PreOpaque);
    });
PostInitViews(GraphBuilder);
```

## Execution Layer

### CPU Path: VectorVM
```cpp
// FNiagaraScriptExecutionContextBase (NiagaraScriptExecutionContext.h)
struct FNiagaraScriptExecutionContextBase {
    UNiagaraScript* Script;
    VectorVM::Runtime::FVectorVMState* VectorVMState;  // VM bytecode state
    TArray<const FVMExternalFunction*> FunctionTable;  // external function delegates
    TArray<void*> UserPtrTable;                         // user pointers for VM
    FNiagaraScriptInstanceParameterStore Parameters;    // shared parameter store
};
```

### GPU Path: Compute Shader
```cpp
// FNiagaraComputeExecutionContext (NiagaraComputeExecutionContext.h)
- FNiagaraRHIUniformBufferLayout (uniform buffer layout)
- FNiagaraGpuSpawnInfoParams (spawn parameters: IntervalDt, InterpStartDt, SpawnGroups)
- References FNiagaraGPUInstanceCountManager, FNiagaraGpuComputeDispatchInterface
```

Both paths share `FNiagaraScriptInstanceParameterStore`, making CPU/GPU switching transparent to upper layers.

## Compilation Path

```
UNiagaraScript (Source: UNiagaraScriptSourceBase)
    │
    ├── FNiagaraCompilationTypes   ← compile type definitions
    ├── NiagaraAsyncCompile        ← async compilation dispatch
    │
    ├── CPU: FNiagaraVMExecutableData → VectorVM bytecode
    └── GPU:  FNiagaraShader → Compute Shader compilation
```

`ENiagaraScriptUsage` determines script purpose: spawn, update, event handling, rendering, etc.

## Data Interface Architecture

```
UNiagaraDataInterfaceBase (UObject)
  └── UNiagaraDataInterface
        ├── PreStageTick() / PostStageTick() lifecycle hooks
        ├── Called via FNiagaraSystemInstance scheduling
        └── 20+ implementations:
              ├── NiagaraDataInterfaceGrid2DCollection / Grid3DCollection
              ├── NiagaraDataInterfaceCurlNoise
              ├── NiagaraDataInterfaceVectorField
              ├── NiagaraDataInterfaceAudio / AudioSpectrum / AudioOscilloscope
              ├── NiagaraDataInterfaceArrayImpl
              ├── NiagaraDataInterfaceCurveBase
              ├── NiagaraDataInterfaceEmitterProperties
              └── ...
```

## UNiagaraSystem Include Dependencies

From `find_include_graph` on `Classes/NiagaraSystem.h`:
```
UNiagaraSystem → NiagaraDataSetCompiledData, NiagaraDataSetAccessor,
                 NiagaraEffectType, NiagaraEmitterHandle,
                 NiagaraParameterCollection, NiagaraParameterDefinitionsSubscriber,
                 NiagaraUserRedirectionParameterStore, NiagaraMessageStore,
                 Particles/FXBudget, Particles/ParticleSystem (legacy compat)
```

## Search Efficiency Data (from this analysis)

| Metric | Value |
|---|---|
| Total tool calls | 37 |
| search_unreal_source | 14 (86% success) |
| get_file_content (anchor) | 22 (64% success) |
| find_include_graph | 1 (100%) |
| Estimated total tokens | ~26,000 |
| Token savings vs full-file | ~97% |
| History-refined results | ~8 of 74 total |
| Best single discovery | Async tick comment in NiagaraSystemSimulation.cpp (1 anchor = ~500 tokens) |

### Anchor Failure Causes
1. **Path inconsistency**: Classes/ vs Public/ vs Internal/ — must try all three
2. **Class vs struct**: Some types declared as `struct` not `class` (e.g., FNiagaraVariableBase)
3. **Anchor string mismatch**: Class declaration may span multiple lines or have different formatting

### Search Failure Causes
1. **Trigram minimum**: Queries with terms < 3 chars silently fail
2. **Phrase mismatch**: Long natural-language queries poorly match trigram index
3. **GPU/Shader terms**: "NiagaraComputeShader" not a real class name — real class is FNiagaraComputeExecutionContext
