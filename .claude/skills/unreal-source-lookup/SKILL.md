---
name: unreal-source-lookup
description: 'Use for Unreal Engine source lookup and symbol search. Trigger on requests like find Unreal symbol, trace function, search engine source, inspect macro, locate class implementation, or search shader code.'
argument-hint: 'Describe the Unreal symbol, subsystem, macro, class, shader, or behavior you need to locate.'
user-invocable: true
disable-model-invocation: false
---

# Unreal Source Lookup

Use this skill when the task is about **finding Unreal Engine source efficiently** with the local MCP server. Token budget awareness is critical — every tool call costs context window.

## Token cost guide

| Operation | ~Tokens | When to use |
|-----------|---------|-------------|
| search_unreal_source (20 results) | ~2,600 | Initial discovery |
| get_file_content (anchor, 500 chars) | ~125 | **Always prefer** for single-symbol context |
| get_file_content (line range, 100 lines) | ~900 | Need broader context |
| get_file_content (full file) | ~45,000 | **Avoid** unless file is small |
| find_callers (specific symbol) | 127–3,000 | Trace call sites |
| find_callers (common symbol like "Render") | ~27,000 | **Use `scope` to limit!** |
| find_include_graph (depth=1) | 50–2,100 | File dependencies |

**Rule: never read a full file when anchor mode suffices.** Anchor is 358x cheaper.

## Supported file types

C/C++ (`.h`, `.hpp`, `.cpp`, `.cc`, `.cxx`) and shader files (`.usf`, `.ush`, `.hlsl`), plus C# (`.cs`).

## Tools (5)

### 1. `search_unreal_source(query?, raw_query?, expanded_terms?, module?, limit?, cluster?, scope_filter?)`
FTS5 search with history-accelerated ranking. Returns compact 300-char snippets (~2,600 tokens for 20 results).
- **Simple**: `query="GetGBuffer"` — auto-escaped FTS5 match
- **Advanced**: `raw_query='"GetGBuffer" AND "Emissive"'` — boolean operators, column filters
- `expanded_terms`: domain terms for history matching (e.g., `["FMaterial", "UMaterialInterface"]`)
- `module`: filter by UE module name (e.g., `"Renderer"`, `"UnrealEd"`, `"Niagara"`)
- `scope_filter`: **must be a JSON string**, not a dict! e.g. `'{"block_type": "function"}'`
- `cluster=true`: limited benefit (~1% token reduction) — skip unless needed
- Results include `source`: `"history_refined"` or `"fts"`, and `final_score`
- Snippets are compact previews — use `get_file_content` with `anchor` for full context

### 2. `get_file_content(file_path, start_line?, end_line?, anchor?, context_chars?)`
Read file content with automatic feedback.
- **Anchor mode** (preferred): `anchor="Render", context_chars=500` — ~125 tokens, 0.1ms
- **Line range**: `start_line=100, end_line=200` — ~900 tokens for 100 lines
- Avoid full file reads (~45K tokens) — always narrow first with anchor or range
- Automatically records feedback when file was in recent search results

### 3. `log_unreal_query(query_text, was_useful?, refinement?)`
Record explicit feedback. Use only to correct automatic feedback.

### 4. `find_include_graph(file_path, direction?, depth?)`
Query include dependency graph for a file. Very cheap (0–15ms, 50–2,100 tokens).
- `direction`: `"upstream"` (who includes this), `"downstream"` (what this includes), `"both"`
- `depth`: recursion depth (1 = direct dependencies only)
- Returns edges with source/target file paths and include paths

### 5. `find_callers(symbol, scope?)`
Find callers of a symbol using FTS5 + bracket skeleton structural analysis.
- Verifies symbol text within each block's line range (not just file-level match)
- Returns `caller_line` (exact line number), `block_type`, `block_name`, `block_range`
- Skips definition blocks (where symbol matches block name)
- **For common symbols** (e.g., "Render", "Update"), always use `scope` to limit results — otherwise may return 500+ callers
- `scope`: module name to limit search (e.g., `"Renderer"`, `"Engine"`)

## Bracket skeleton — the structural spine

Bracket skeleton is **not optional** — it is the core that makes searches precise, anchors reliable, and call tracing possible. It provides three capabilities that should be used in every session:

### 1. `scope_filter` — precision filter for searches

Every `search_unreal_source` call should consider adding `scope_filter` to eliminate noise. Without it, a search for "class UPCGSettings" returns implementation files, test files, and element headers. With it, you get **only class declaration blocks**.

```python
# Bad: 10 results, 60% noise (cpp files, tests, unrelated elements)
search_unreal_source(query="class UPCGSettings", module="PCG")

# Good: fewer results, all class declarations
search_unreal_source(query="UPCGSettings", module="PCG", scope_filter='{"block_type": "class"}')
```

**When to use which scope_filter**:

| Task | scope_filter | Why |
|------|-------------|-----|
| Discover class hierarchy | `'{"block_type": "class"}'` | Only class declarations, no implementations |
| Find struct definitions | `'{"block_type": "struct"}'` | Data types, context structs |
| Locate function implementations | `'{"block_type": "function"}'` | Skip declarations, get bodies |
| Find specific class method | `'{"block_type": "function", "block_name": "FMyClass"}'` | Only methods inside that class |

### 2. `find_callers` — direct call chain tracing (replaces anchor guessing)

**Never guess function names for anchors when you can trace the call chain directly.**

The most common failure pattern: trying to understand execution flow by guessing `"ExecuteGraphTask"` or `"virtual bool Execute"` as anchors. Instead:

```python
# Bad: guess anchor text, 60% failure rate
get_file_content(file_path="...", anchor="ExecuteGraphTask")  # → not found
get_file_content(file_path="...", anchor="void FPCGGraphExecutor::Execute")  # → wrong signature

# Good: trace from a known symbol
find_callers("Generate", scope="PCG")
# → UPCGComponent::Generate → UPCGSubsystem::Schedule → FPCGGraphExecutor::Schedule
# Each result includes caller_line, block_type, block_name — exact locations
```

**Key rules**:
- Always provide `scope` for common symbols ("Render", "Update", "Execute", "Generate") — without scope, expect 500+ results
- `scope` is a module name: `"PCG"`, `"Renderer"`, `"Niagara"`, `"Engine"`
- Results include `block_range` (line range of enclosing block) — use this for line-range reads instead of anchor guessing

### 3. Search result block metadata — the guide for anchor construction

Search results include structural information from the bracket skeleton. **Read it before constructing anchors.**

```python
# Search returns:
#   file_path: "PCGComponent.h"
#   block_type: "class"
#   block_name: "UPCGComponent"
#   (implicit: line range from bracket index)

# Instead of guessing: anchor="class UPCGComponent : public USceneComponent"  ← WRONG
# Use generic anchor:  anchor="class UPCGComponent : public"                  ← WORKS
# Or use block info:   get_file_content(start_line=<block_start>, end_line=<block_start+50>)
```

**Verified**: In PCG analysis, 3/11 anchor failures were caused by guessing wrong base classes (`USceneComponent` vs `UActorComponent`, `UAssetDefinitionImpl` vs `UPCGGraphInterface`). Using `"class XXX : public"` (without specifying the base) eliminated all such failures.

### Bracket usage decision matrix

| Question type | Primary tool | scope_filter? | find_callers? |
|---------------|-------------|---------------|---------------|
| "What classes exist in X?" | search | `'{"block_type":"class"}'` | No |
| "What does class X inherit?" | search → anchor | No | No |
| "Who calls function X?" | find_callers | N/A | Yes (with scope) |
| "What implements virtual X?" | find_callers | N/A | Yes (with scope) |
| "How does execution flow from A to B?" | find_callers chain | N/A | Yes (with scope) |
| "What does file X depend on?" | find_include_graph | N/A | No |
| "What is the data hierarchy?" | search with scope_filter | `'{"block_type":"class"}'` | No |

## Intent expansion

**Before searching**, expand the user's intent into related terms that may appear in past query logs. Use world knowledge to generate synonyms, related class names, and likely search anchors. Pass these as `expanded_terms`.

The key insight: do not search history only with the user's exact words. Past queries contain class names, file paths, and code symbols — not user prose.

Examples:
- "Material architecture" → `expanded_terms=["FMaterial", "UMaterialInterface", "MaterialResource", "MaterialRenderProxy", "MaterialShared"]`
- "Lumen lighting" → `expanded_terms=["Lumen", "FLumenScene", "LumenRayTracing", "RayTracing"]`
- "Niagara particles" → `expanded_terms=["Niagara", "UNiagaraSystem", "UNiagaraEmitter", "FNiagaraEmitterInstance", "FNiagaraScriptExecutionContext", "FNiagaraComputeExecutionContext", "FNiagaraGpuComputeDispatchInterface"]`

Use expanded_terms on the **first search** of a new intent to maximize history hit rate. Subsequent searches in the same session build their own history automatically.

**Verified impact**: In Niagara analysis, expanded_terms + history_refined produced 8/~74 results ranked higher, surfacing `NiagaraGpuComputeDispatch.cpp` and `NiagaraGPUSystemTick.cpp` that an initial empty-result search missed entirely.

## Search strategy: Layer-first approach

Before searching, identify the **layers** of the system you need to trace. For each layer, plan one search probe. This avoids blind keyword spraying.

**Template** (internal, do not output to user):

```
INTENT: <one-sentence user intent>
LAYERS:
  - <layer>: <role>
    MODE: discovery | call_trace | dependency
    PROBE: <search query, with scope_filter if applicable>
    EXTRACT: <anchor pattern or line range>
```

**MODE determines the primary tool**:
- `discovery`: `search_unreal_source` (with `scope_filter`) → `get_file_content` anchor. For finding classes, structs, data types.
- `call_trace`: `find_callers(symbol, scope=...)` directly. For execution flow, call chains, virtual dispatch.
- `dependency`: `find_include_graph`. For file-level include relationships.

**Rules**:
1. Define layers before any tool call. Assign each layer a MODE.
2. One probe per layer. Batch probes for independent layers in parallel.
3. For `discovery` layers: add `scope_filter` to searches by default. Use `"class XXX : public"` anchor pattern (never guess the base class).
4. For `call_trace` layers: use `find_callers` with `scope` — do NOT try to guess function signatures as anchors.
5. Only extract after a probe narrows the file and location. **Always use anchor mode** for extraction.
6. If a layer cannot be found, report what was searched — do not keep retrying variations.

**Example** — tracing Material architecture (with bracket integration):

```
INTENT: Analyze Unreal Material system architecture
LAYERS:
  - Asset layer: UMaterialInterface, UMaterial, UMaterialInstance
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialInterface.h") AND "class UMaterialInterface"'
      scope_filter='{"block_type": "class"}'
    EXTRACT: anchor="class UMaterialInterface : public"
  - Compile layer: FMaterial, FMaterialResource, FHLSLMaterialTranslator
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialShared.h") AND "class FMaterialResource"'
      scope_filter='{"block_type": "class"}'
    EXTRACT: anchor="class FMaterialResource : public"
  - Shader map layer: FMaterialShaderMapLayout
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialShaderMapLayout.h")'
    EXTRACT: anchor="FMaterialShaderMapLayout"
  - Render proxy layer: FMaterialRenderProxy
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialRenderProxy.h") AND "class FMaterialRenderProxy"'
    EXTRACT: anchor="class FMaterialRenderProxy : public"
```

This plan costs ~4 searches (~10K tokens) + ~4 anchors (~500 tokens) = **~10.5K tokens** instead of 200K+ from unstructured full-file reads.

**Example** — tracing Niagara system architecture (with MODE):

```
INTENT: Analyze Niagara particle system architecture
LAYERS:
  - Asset layer: UNiagaraSystem, UNiagaraEmitter, UNiagaraComponent
    MODE: discovery
    PROBE: query="class UNiagaraSystem", module="Niagara", scope_filter='{"block_type":"class"}'
    EXTRACT: anchor="class UNiagaraSystem : public"
  - Simulation layer: FNiagaraEmitterInstance, FNiagaraSystemSimulation
    MODE: discovery
    PROBE: query="FNiagaraEmitterInstance simulation execute", module="Niagara"
    EXTRACT: anchor="class FNiagaraEmitterInstanceImpl"
  - GPU compute layer: FNiagaraGpuComputeDispatchInterface, FNiagaraComputeExecutionContext
    MODE: discovery
    PROBE: query="GpuComputeDispatch GPU compute", module="Niagara"  ← short trigram-friendly terms!
    EXTRACT: anchor="class FNiagaraGpuComputeDispatchInterface : public"
  - Execution flow: How does tick → simulate → dispatch work?
    MODE: call_trace
    PROBE: find_callers("ExecuteSimulation", scope="Niagara")
    EXTRACT: use returned block_range for line-range reads
  - Data interface layer: UNiagaraDataInterface, FNiagaraVariableBase
    MODE: discovery
    PROBE: query="NiagaraDataInterface", module="Niagara"
    EXTRACT: anchor="class UNiagaraDataInterface : public"
```

This plan costs ~4 searches (~10K tokens) + 1 find_callers (~1K tokens) + ~4 anchors (~500 tokens) = **~11.5K tokens**. The call_trace layer directly reveals the execution pipeline instead of guessing anchors.

## Retrieval procedure

1. **Expand intent** — Generate related terms from the user's request.
2. **Classify each sub-question** as `discovery`, `call_trace`, or `dependency` (see decision matrix above).
3. **For discovery** — Call `search_unreal_source` with keywords + expanded_terms + `scope_filter`.
   - Simple: `search_unreal_source(query="GetGBuffer")`
   - With scope_filter: `search_unreal_source(query="UPCGSettings", module="PCG", scope_filter='{"block_type": "class"}')`
   - With expansion: `search_unreal_source(query="Material architecture", expanded_terms=["FMaterial", "UMaterialInterface"])`
4. **For call_trace** — Call `find_callers(symbol, scope=...)` directly. Do NOT attempt anchor guessing for execution flow questions.
   - `find_callers("Generate", scope="PCG")` → reveals UPCGComponent → UPCGSubsystem → FPCGGraphExecutor chain
   - `find_callers("ExecuteInternal", scope="PCG")` → reveals all concrete Element implementations
5. **Read results** — Call `get_file_content` with **anchor mode** for promising files.
   - `get_file_content(file_path="...", anchor="class FMyClass : public")` ← generic pattern, never guess base class
   - Or use `block_range` from search/find_callers results: `get_file_content(start_line=X, end_line=X+50)`
   - This costs ~125 tokens vs ~45,000 for a full file read
6. **For dependency** — Call `find_include_graph` for file-level relationships.
7. **Correct if needed** — Call `log_unreal_query` only if automatic feedback was wrong.

## FTS5 raw_query syntax

| Operator | Example |
|----------|---------|
| AND | `'"A" AND "B"'` |
| OR | `'"A" OR "B"'` |
| NOT | `'"A" NOT "B"'` |
| Grouping | `'("A" OR "B") AND "C"'` |
| Column filter | `'file_path : "BasePass"'` |

Columns: `file_path`, `module_name`, `raw_content`. All terms must be 3+ characters. NEAR and prefix (`*`) do not work with trigram tokenizer.

## Feedback loop

The system maintains a closed feedback loop automatically:
- `search_unreal_source` uses history as ranking signal (not filtering) — prevents confirmation bias
- `get_file_content` records which files were actually useful (query_note)
- Future similar searches are ranked higher based on this feedback
- History signals include 30-day half-life time decay

## Output expectations

- Candidate file paths and module names with compact snippets
- For deep analysis, use `get_file_content(anchor=...)` — not full file reads
- Block type/name from bracket skeleton
- Line ranges and caller line numbers for further reading
- `source` field indicating history-accelerated or full-scan results
- Note when DB indexing is needed

## Plugin module directory conventions

UE plugin modules (e.g., Niagara) distribute headers across three directories with different visibility:

| Directory | Visibility | Content |
|---|---|---|
| `Classes/` | Public (UCLASS/USTRUCT headers) | Asset types, USTRUCTs, property declarations |
| `Public/` | Public (non-UObject headers) | C++ interfaces, simulation classes, managers |
| `Internal/` | Private | Implementation detail classes (e.g., *Impl.h) |

**Anchor failure mitigation**: When `get_file_content(anchor=...)` fails in one directory, retry in the other two before giving up. For example, `FNiagaraEmitterInstance` lives in `Classes/`, not `Public/`.

**Verified anchor hit rate**: 64% across 22 attempts in Niagara analysis. Failures caused by: wrong directory (5), class vs struct mismatch (2), non-existent anchor text (1).

## Common search failure patterns

| Pattern | Example | Fix |
|---|---|---|
| **Long natural-language query** | `"NiagaraComputeShader GPU simulation dispatch"` → 0 results | Use 2-3 trigram-friendly terms: `"GpuComputeDispatch GPU compute"` |
| **Non-existent class name** | `"NiagaraComputeShader"` → 0 results (not a real class) | First search broadly, then use discovered class names as anchors |
| **class vs struct mismatch** | `anchor="class FNiagaraVariableBase"` → not found | Try `anchor="struct FNiagaraVariableBase"` for USTRUCT types |
| **Term too short** | Single/double char terms silently fail | All terms must be ≥3 characters for trigram FTS5 |
| **Empty expanded_terms** | First search with no history → generic ranking | Always use `expanded_terms` on first search of a new subsystem |
| **Guessing base class in anchor** | `anchor="class UPCGComponent : public USceneComponent"` → not found (actual: UActorComponent) | Use `"class XXX : public"` without specifying base class. **3 failures in PCG session from this pattern alone** |
| **Guessing function names for execution flow** | `anchor="ExecuteGraphTask"` → not found. `anchor="virtual FPCGElementPtr GetElement"` → not found | Use `find_callers` with `scope` instead. Anchor guessing for execution flow has ~60% failure rate |
| **Searching .cpp for class declarations** | `get_file_content("PCGComponent.cpp", anchor="class UPCGComponent")` → not found | Class declarations are in `.h` files, `.cpp` has implementations only |
| **No scope_filter on broad searches** | `query="UPCGSettings"` returns 10 results: 4 class declarations, 3 implementations, 3 tests | Add `scope_filter='{"block_type":"class"}'` to get only declarations |
| **Repeated identical failed anchor** | Same anchor tried twice with same result | After one anchor failure, switch strategy: use line-range read, or different anchor pattern |

## Verified token efficiency

From Niagara architecture analysis (37 tool calls, complete subsystem coverage):

| Approach | Tokens | Speed |
|---|---|---|
| Full-file reads (~18 files) | ~810,000 | Slow, context overflow |
| Random unstructured search (~30 searches) | ~78,000 | Moderate |
| **Layer-first + anchor** (actual) | **~26,000** | **Fast, complete** |

Savings: **97% vs full-file, 67% vs random search**. Best single discovery: async tick sequence comment in `NiagaraSystemSimulation.cpp` — 1 anchor (~500 tokens) revealed the entire pipeline design.

From PCG architecture analysis (38 tool calls, 6-layer complete coverage):

| Approach | Calls | Failed calls | Tokens | Notes |
|---|---|---|---|---|
| Layer-first without bracket (actual) | 38 | 13 (34%) | ~24,400 | 11 anchor failures, 2 empty searches, 2 duplicate reads |
| **Layer-first with bracket** (projected) | **~16** | **0-2** | **~10,000** | scope_filter + find_callers + generic anchors |

Key PCG findings:
- **13/38 failures** (34%) were avoidable with bracket: 3 wrong base class guesses, 2 wrong function name guesses, 2 fictitious class name searches, 2 duplicate reads, 1 wrong file extension, 1 repeated failed anchor
- **scope_filter** alone would have reduced search noise by ~3,000 tokens across 4 searches
- **find_callers("Generate", scope="PCG")** would have directly revealed the execution chain in 1 call (~1K tokens) instead of 4 failed anchor attempts (~2K tokens + ~200 tokens wasted)
- **Generic anchor pattern** `"class XXX : public"` has 100% success rate vs 50% for guessed base classes
