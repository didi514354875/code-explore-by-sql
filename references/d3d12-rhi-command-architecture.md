# D3D12 RHI Command Buffer Recording Architecture

Source: UE5 source code analysis via FTS5 search (2025-05-22 session).

## Key Files

| File | Purpose |
|------|---------|
| `RHI/Public/RHICommandList.h` | FRHICommandListBase, command chain, FRHICommandBase |
| `D3D12RHI/Private/D3D12CommandContext.h` | FD3D12CommandContext, FD3D12ContextCommon, FD3D12CommandContextBase |
| `D3D12RHI/Private/D3D12CommandList.h` | FD3D12CommandList, FD3D12CommandAllocator |
| `D3D12RHI/Private/D3D12Submission.h` | FD3D12Payload, FD3D12SyncPoint, FD3D12Fence |
| `D3D12RHI/Private/D3D12PipelineState.h` | FD3D12GraphicsPipelineState |
| `D3D12RHI/Private/D3D12Commands.cpp` | RHI method implementations (DrawPrimitive, SetPSO, etc.) |

## Class Hierarchy

```
FRHICommandBase                          // Abstract command node (linked list)
├── TRHILambdaCommand<CmdList, Lambda>   // Lambda-based command (modern approach)
├── TRHILambdaCommandMultiPipe           // Multi-pipeline lambda
└── [Typed RHI commands]                 // FRHICommandBeginRenderPass, etc.

FRHICommandListBase                      // Command recording + linear allocator
├── FRHICommandList                      // Deferred command list (parallel rendering)
├── FRHICommandListImmediate             // Immediate execution (no RHI thread)
├── FRHISubCommandList                   // Sub-list for parallel render passes
└── FRHIComputeCommandList               // Compute-only command list

IRHICommandContext                       // Platform-agnostic graphics command interface
IRHIComputeContext                       // Platform-agnostic compute command interface

FD3D12CommandContextBase                 // Base: MGPU routing, implements IRHICommandContext
├── FD3D12CommandContextRedirector       // MGPU: broadcasts to per-GPU contexts
│   └── FD3D12CommandContext             // Per-GPU physical context (THE main class)
│       ├── FD3D12ContextCommon          // Command list lifecycle, payload management
│       │   └── FD3D12CommandList        // Wraps ID3D12GraphicsCommandList*
│       └── FD3D12DeviceChild            // Device ownership
└── FD3D12ContextCopy                    // Copy queue context (no RHI interface)

FD3D12ContextCommon                      // Manages recording → Finalize → Payloads[]
├── FD3D12CommandList*                   // Current active D3D12 command list
├── FD3D12CommandAllocator*              // Reusable command allocator
├── TArray<FD3D12Payload*>              // Recorded payloads for submission
└── FD3D12BarriersFactory               // Batched resource barriers
```

## Command Flow: DrawPrimitive Example

```
1. Renderer calls:
   RHICmdList.DrawPrimitive(BaseVertex, NumPrimitives, NumInstances)

2. FRHICommandListBase checks Bypass():
   ├── Bypass=true  → directly call Context->RHIDrawPrimitive(...)
   └── Bypass=false → ALLOC_COMMAND into linked list via FMemStackBase

3. RHI thread executes command chain:
   FRHICommandListBase::Execute() → iterate linked list
   → each command.ExecuteAndDestruct()

4. FD3D12CommandContext::RHIDrawPrimitive():
   CommitNonComputeShaderConstants()    // Flush dirty constants
   FlushResourceBarriers()              // Batch barriers
   GraphicsCommandList()->DrawInstanced(...)  // D3D12 API call

5. Finalize:
   FD3D12ContextCommon::Finalize()
   → CommandList->Close()
   → Package as FD3D12Payload

6. Submission thread:
   FD3D12Queue::Submit()
   → ExecuteCommandLists(payload)
   → GPU executes
```

## Key Design Patterns

### 1. Command Defer vs Immediate (Bypass Mode)
`Bypass()` returns true when no RHI thread exists. In bypass mode, RHI calls go directly to the platform implementation. Otherwise, commands are recorded into a linked list for deferred execution on the RHI thread.

### 2. Linear Allocator (FMemStackBase)
Commands are allocated from a memory stack — no per-command malloc. The entire command list is freed at once after execution. This makes command recording extremely cheap.

### 3. Command List Splitting
`ConditionalSplitCommandList()` checks `D3D12.MaxCommandsPerCommandList` cvar. When exceeded, the current command list is closed and a new one opened. This prevents single command lists from becoming too large.

### 4. State Caching (FD3D12StateCache)
Caches current PSO, vertex buffers, index buffers, shader resource views, samplers, etc. Avoids redundant D3D12 API calls by checking if state actually changed before calling the driver.

### 5. Batched Resource Barriers
`FD3D12BarriersFactory` accumulates resource transitions. `FlushResourceBarriers()` submits them in a single batch before draw calls, minimizing driver overhead.

### 6. Payload System
`FD3D12Payload` encapsulates: command lists + sync points (wait/signal) + residency set. The submission thread processes payloads asynchronously, decoupling recording from GPU submission.

### 7. Sync Points
`FD3D12SyncPoint` abstracts GPU synchronization. Maps to D3D12 Fence values internally. One-shot, ref-counted. Can be GPU-only (no CPU notification) or GPU+CPU (with FGraphEvent for CPU wait/poll).

### 8. MGPU via Redirector
`FD3D12CommandContextRedirector` broadcasts commands to per-GPU `FD3D12CommandContext` instances. Each physical context has its own command list and submission queue.
