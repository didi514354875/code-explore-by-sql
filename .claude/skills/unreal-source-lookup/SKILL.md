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

## Intent expansion

**Before searching**, expand the user's intent into related terms that may appear in past query logs. Use world knowledge to generate synonyms, related class names, and likely search anchors. Pass these as `expanded_terms`.

The key insight: do not search history only with the user's exact words. Past queries contain class names, file paths, and code symbols — not user prose.

Examples:
- "Material architecture" → `expanded_terms=["FMaterial", "UMaterialInterface", "MaterialResource", "MaterialRenderProxy", "MaterialShared"]`
- "Lumen lighting" → `expanded_terms=["Lumen", "FLumenScene", "LumenRayTracing", "RayTracing"]`
- "Niagara particles" → `expanded_terms=["Niagara", "FNiagaraSystem", "FNiagaraEmitter", "NiagaraScript"]`

Use expanded_terms on the **first search** of a new intent to maximize history hit rate. Subsequent searches in the same session build their own history automatically.

## Search strategy: Layer-first approach

Before searching, identify the **layers** of the system you need to trace. For each layer, plan one search probe. This avoids blind keyword spraying.

**Template** (internal, do not output to user):

```
INTENT: <one-sentence user intent>
LAYERS:
  - <layer>: <role>
    PROBE: <search query or raw_query>
    EXTRACT: <anchor or line range, only after probe succeeds>
```

**Rules**:
1. Define layers before any tool call.
2. One probe per layer. Batch probes for independent layers in parallel.
3. Only extract after a probe narrows the file and location. **Always use anchor mode** for extraction.
4. Use `find_callers` to trace call sites (with `scope` for common symbols), `find_include_graph` for dependencies.
5. If a layer cannot be found, report what was searched — do not keep retrying variations.

**Example** — tracing Material architecture:

```
INTENT: Analyze Unreal Material system architecture
LAYERS:
  - Asset layer: UMaterialInterface, UMaterial, UMaterialInstance
    PROBE: raw_query='(file_path : "MaterialInterface.h") AND "class UMaterialInterface"'
    EXTRACT: anchor="class UMaterialInterface : public UObject"
  - Compile layer: FMaterial, FMaterialResource, FHLSLMaterialTranslator
    PROBE: raw_query='(file_path : "MaterialShared.h") AND "class FMaterialResource"'
    EXTRACT: anchor="class FMaterialResource : public FMaterial"
  - Shader map layer: FMaterialShaderMapLayout
    PROBE: raw_query='(file_path : "MaterialShaderMapLayout.h")'
    EXTRACT: anchor="FMaterialShaderMapLayout"
  - Render proxy layer: FMaterialRenderProxy
    PROBE: raw_query='(file_path : "MaterialRenderProxy.h") AND "class FMaterialRenderProxy"'
    EXTRACT: anchor="class FMaterialRenderProxy"
```

This plan costs ~4 searches (~10K tokens) + ~4 anchors (~500 tokens) = **~10.5K tokens** instead of 200K+ from unstructured full-file reads.

## Retrieval procedure

1. **Expand intent** — Generate related terms from the user's request.
2. **Search** — Call `search_unreal_source` with keywords + expanded_terms.
   - Simple: `search_unreal_source(query="GetGBuffer")`
   - With expansion: `search_unreal_source(query="Material architecture", expanded_terms=["FMaterial", "UMaterialInterface"])`
   - Advanced: `search_unreal_source(raw_query='"GetGBuffer" AND "Emissive"')`
3. **Read results** — Call `get_file_content` with **anchor mode** for promising files.
   - `get_file_content(file_path="...", anchor="void FMyClass::MyMethod")`
   - This costs ~125 tokens vs ~45,000 for a full file read
4. **Trace structure** — Use `find_callers` (with `scope` for common symbols) for call sites, `find_include_graph` for dependencies.
5. **Correct if needed** — Call `log_unreal_query` only if automatic feedback was wrong.

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
