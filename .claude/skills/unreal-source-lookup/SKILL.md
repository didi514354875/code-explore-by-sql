---
name: unreal-source-lookup
description: 'Use for Unreal Engine source lookup and symbol search. Trigger on requests like find Unreal symbol, trace function, search engine source, inspect macro, locate class implementation, or search shader code.'
argument-hint: 'Describe the Unreal symbol, subsystem, macro, class, shader, or behavior you need to locate.'
user-invocable: true
disable-model-invocation: false
---

# Unreal Source Lookup

Use this skill when the task is about **finding Unreal Engine source efficiently** with the local MCP server.

## Supported file types

C/C++ (`.h`, `.cpp`, `.cs`) and shader files (`.usf`, `.ush`, `.hlsl`).

## Tools (3)

1. **`search_unreal_source(query?, raw_query?, expanded_terms?, module?, limit?)`** — Search with automatic history acceleration.
   - System searches query_logs for similar past queries first, then falls back to full FTS5.
   - Results include `source` field: `"history_refined"` (accelerated) or `"fts"` (full scan).
   - Each search is automatically logged in query_logs.
   - `expanded_terms`: optional extra keywords from intent expansion (see below).
2. **`get_file_content(file_path, start_line?, end_line?, anchor?)`** — Read file content.
   - Automatically records feedback in query_note when the file was in recent search results.
   - Prefer anchor mode: `get_file_content(file_path="...", anchor="void FMyClass::MyMethod")`.
3. **`log_unreal_query(query_text, was_useful?, refinement?)`** — Explicit feedback (optional).
   - Use only to correct automatic feedback.

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
3. Only extract after a probe narrows the file and location.
4. Do not extract callees or sub-components unless directly asked.
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
    EXTRACT: full file (small)
  - Render proxy layer: FMaterialRenderProxy
    PROBE: raw_query='(file_path : "MaterialRenderProxy.h") AND "class FMaterialRenderProxy"'
    EXTRACT: anchor="class FMaterialRenderProxy"
```

This plan costs ~4 searches + ~4 extracts = **~8 tool calls** instead of 20+ from unstructured exploration.

## Retrieval procedure

1. **Expand intent** — Generate related terms from the user's request.
2. **Search** — Call `search_unreal_source` with keywords + expanded_terms.
   - Simple: `search_unreal_source(query="GetGBuffer")`
   - With expansion: `search_unreal_source(query="Material architecture", expanded_terms=["FMaterial", "UMaterialInterface", "MaterialResource"])`
   - Advanced: `search_unreal_source(raw_query='"GetGBuffer" AND "Emissive"')`
   - Results include `source`: `"history_refined"` or `"fts"`.

3. **Read results** — Call `get_file_content` for promising files. Feedback is automatic.

4. **Correct if needed** — Call `log_unreal_query` only if automatic feedback was wrong.


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
- `search_unreal_source` checks history first (query_logs LIKE OR + query_note ranking)
- `get_file_content` records which files were actually useful (query_note)
- Future similar searches are faster and more accurate based on this feedback

## Output expectations

- Candidate file paths and module names
- Code snippets from FTS5
- Line ranges for further reading
- `source` field indicating history-accelerated or full-scan results
- Note when DB indexing is needed
