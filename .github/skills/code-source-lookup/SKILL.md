---
name: code-source-lookup
description: 'Use for source code lookup and symbol search. Trigger on requests like find symbol, trace function, search source, inspect macro, locate class implementation, or search code.'
argument-hint: 'Describe the symbol, subsystem, macro, class, or behavior you need to locate.'
user-invocable: true
disable-model-invocation: false
---

# Code Source Lookup

Use this skill when the task is about **finding source code efficiently** with the local MCP server. Token budget awareness is critical — every tool call costs context window.

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
- `module`: filter by module name (e.g., `"Renderer"`, `"Core"`, `"Editor"`)
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

## Intent expansion

**Before searching**, expand the user's intent into related terms that may appear in past query logs. Use world knowledge to generate synonyms, related class names, and likely search anchors. Pass these as `expanded_terms`.

The key insight: do not search history only with the user's exact words. Past queries contain class names, file paths, and code symbols — not user prose.

Examples:
- "Material architecture" → `expanded_terms=["FMaterial", "UMaterialInterface", "MaterialResource", "MaterialRenderProxy"]`
- "Rendering pipeline" → `expanded_terms=["FRenderer", "RenderPass", "FScene", "FViewInfo"]`
- "Particle system" → `expanded_terms=["ParticleSystem", "FParticleEmitter", "ParticleModule"]`

Use expanded_terms on the **first search** of a new intent to maximize history hit rate. Subsequent searches in the same session build their own history automatically.

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

**Example** — tracing a rendering system:

```
INTENT: Analyze rendering material system architecture
LAYERS:
  - Asset layer: UMaterialInterface, UMaterial, UMaterialInstance
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialInterface.h") AND "class UMaterialInterface"'
    EXTRACT: anchor="class UMaterialInterface : public"
  - Compile layer: FMaterial, FMaterialResource
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialShared.h") AND "class FMaterialResource"'
    EXTRACT: anchor="class FMaterialResource : public"
  - Render proxy layer: FMaterialRenderProxy
    MODE: discovery
    PROBE: raw_query='(file_path : "MaterialRenderProxy.h") AND "class FMaterialRenderProxy"'
    EXTRACT: anchor="class FMaterialRenderProxy : public"
```

This plan costs ~3 searches (~8K tokens) + ~3 anchors (~400 tokens) = **~8.4K tokens** instead of 200K+ from unstructured full-file reads.

## Retrieval procedure

1. **Expand intent** — Generate related terms from the user's request.
2. **Classify each sub-question** as `discovery`, `call_trace`, or `dependency`.
3. **For discovery** — Call `search_unreal_source` with keywords + expanded_terms + `scope_filter`.
   - Simple: `search_unreal_source(query="GetGBuffer")`
   - With scope_filter: `search_unreal_source(query="MyClass", scope_filter='{"block_type": "class"}')`
   - With expansion: `search_unreal_source(query="Material architecture", expanded_terms=["FMaterial", "UMaterialInterface"])`
4. **For call_trace** — Call `find_callers(symbol, scope=...)` directly.
5. **Read results** — Call `get_file_content` with **anchor mode** for promising files.
   - `get_file_content(file_path="...", anchor="class FMyClass : public")` ← generic pattern, never guess base class
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
