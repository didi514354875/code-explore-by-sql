---
name: code-source-lookup
description: 'Use for source code lookup and symbol search. Trigger on requests like find symbol, trace function, search source, inspect macro, locate class implementation, or search code.'
argument-hint: 'Describe the symbol, subsystem, macro, class, or behavior you need to locate.'
user-invocable: true
disable-model-invocation: false
---

# Code Source Lookup

Efficient source code lookup using the local MCP server.

## Token cost guide

| Operation | ~Tokens | When to use |
|-----------|---------|-------------|
| search_code_source (20 results) | 2,600 | Initial discovery |
| get_file_content (anchor, 500 chars) | 125 | **Always prefer** for single-symbol context |
| get_file_content (line range, 100 lines) | 900 | Need broader context |
| get_file_content (full file) | 45,000 | **Avoid** unless file is small |
| find_callers (specific symbol) | 127–3,000 | Trace call sites |
| find_callers (common symbol) | ~27,000 | **Use `scope` to limit!** |
| find_include_graph (depth=1) | 50–2,100 | File dependencies |

## Tools (5)

### `search_code_source(query?, raw_query?, expanded_terms?, module?, limit?, cluster?, scope_filter?)`
FTS5 search with history-accelerated ranking (~2,600 tokens/20 results).
- Simple: `query="GetGBuffer"` / Advanced: `raw_query='"A" AND "B"'`
- `expanded_terms`: domain class/symbol names for ranking boost (e.g. `["FMaterial"]`)
- `module` / `scope_filter` / `cluster` — see Bracket skeleton section
- Results include `source` (history_refined or fts) and `final_score`

### `get_file_content(file_path, start_line?, end_line?, anchor?, context_chars?)`
Read file via anchor (preferred) or line range. Auto-records feedback.
- anchor="Render", context_chars=500 → ~125 tokens, 0.1ms
- start_line=100, end_line=200 → ~900 tokens for 100 lines
- Avoid full file reads (~45K tokens)

### `log_code_query(query_text, was_useful?, refinement?)`
Record explicit feedback. Only needed to correct automatic feedback.

### `find_include_graph(file_path, direction?, depth?)`
File dependency query. direction: upstream (who includes this) / downstream / both. depth: recursion level.

### `find_callers(symbol, scope?)`
Find callers using bracket skeleton analysis. Returns caller_line, block_type/name, block_range.
- Always use `scope` for common symbols (Render, Update, etc.)
- `scope`: module name — derived from `Engine/Source/<Category>` in the file path (see [[unreal-source-module-structure]])

## Bracket skeleton — structural spine

Bracket skeleton provides three capabilities used in every session.

### 1. scope_filter — block-type filter for `search_code_source`

**Accepts dict or JSON string.** Param format:

| Field | Required | Valid values |
|-------|----------|-------------|
| `block_type` | No | namespace / class / enum / function / control_flow / macro / unknown |
| `block_name` | No | Exact block name, case-insensitive |

> Note: `struct X` and `class X` are **both** classified as `block_type="class"`. There is no `"struct"` type.

**Passing format (verified)**:
```
✓ scope_filter={"block_type": "class"}                                         ← dict (preferred)
✓ scope_filter="{\"block_type\": \"class\"}"                                   ← JSON string
✓ scope_filter={"block_type": "function", "block_name": "Render"}              ← dict
✗ scope_filter='{"block_type": "class"}'                                       ← single-quotes: may be parsed as str, not valid JSON
```

**When scope_filter errors → fallback**: Use raw_query column filter instead:
`raw_query='(file_path : "MaterialShared") AND "FMaterial"'` or `(module_name : "Runtime")`

**block_type classification** (from `symbol_sniffer.py`):

| type | matches |
|------|---------|
| class | `class X` / `struct X` |
| enum | `enum X` / `enum class X` |
| function | block ending with `)`, not control-flow |
| namespace | `namespace X` |
| macro | `#define` |
| control_flow | `if`/`for`/`while`/`switch` (non-top-level) |
| unknown | unclassifiable |

### 2. find_callers — when to use (and when not to)

**Use for** → who calls a function, where a virtual is dispatched, where execution enters.
**Don't use for** → data flow, how values are computed/passed, class hierarchies.

```python
# ✓ find_callers("Execute", scope="Renderer")    # who calls Execute
# ✓ search_code_source("class FMaterial")          # structural/type discovery
# ✓ search_code_source("FillUniformBuffer")        # find implementation
```

Results include `block_range` — use for line-range reads instead of guessing anchors.

### 3. Anchor construction

Always use generic anchor patterns from search result metadata:
- search returns `block_type="class", block_name="UMyComponent"` → `anchor="class UMyComponent : public"` (never guess base class)
- Or use block_range: `get_file_content(start_line=N, end_line=N+50)`

Verified: `"class XXX : public"` has 100% success rate vs 50% for guessed base classes.

### Tool decision matrix

| Sub-problem | Primary tool | Secondary |
|------------|-------------|-----------|
| Structure/type definition | search_code_source + scope_filter | anchor |
| Function implementation | search_code_source → anchor | line range |
| Call chain (who calls X?) | find_callers(symbol, scope=...) | block_range |
| Data flow (value A→B) | search_code_source → anchor | find_callers if needed |
| File dependencies | find_include_graph | — |

## Intent expansion

On first search of a new subsystem, pass `expanded_terms` with class/symbol names:
- "Material architecture" → `["FMaterial","UMaterialInterface","MaterialResource","MaterialRenderProxy"]`
- "Particle system" → `["FParticleEmitter","ParticleModule","ParticleSpawnInfo"]`
- "Rendering pipeline" → `["FRenderer","RenderPass","FScene","FViewInfo","FRenderTarget"]`

### Validated effectiveness (real-session data)

| Term type | Example | Outcome |
|-----------|---------|---------|
| Concrete existing class name | `FMaterialUniformExpression`, `FMaterialRenderProxy` | ✅ Precise hit |
| Non-existent class name | `FMaterialUniformBuffer` (correct name is `FUniformExpressionCache`) | ❌ 0 results, wasted slot |
| Pure concept word | `MaterialParameters` | ❌ Noise — Slate/Decal results |

### Rules
- **Only use class names known to exist in the codebase** — don't guess names
- **After first empty result**, if an expanded_term is confirmed non-existent, replace it immediately
- Use symbols, not prose — past queries contain class names, not natural language.
- **First search MUST include `module` param** to narrow to the core module (e.g., `module="Runtime"` or `module="Renderer"`), to exclude plugin noise like Interchange

## Search strategy: Mandatory Layer table

**Before any tool call**, output a Layer table:

```
LAYER TABLE:
  1. [name] — [sub-problem type], MODULE=[Runtime/Renderer/...], PROBE=[tool call], EXTRACT=[method]
  2. ...
```

`MODULE` is mandatory for the first layer's search_code_source call — narrow to the most relevant module (Runtime, Renderer, Engine, Core) to exclude plugin noise.

**Budget hard limits** (enforced — stop at cap, do not justify exceeding):

| Resource | Cap | When exceeded |
|----------|-----|--------------|
| Layers | 6 max | Stop adding layers; output remaining as "not explored" |
| search_code_source | ≤5 calls | **Stop searching.** Summarize what was found, list unknowns. Do NOT add "just one more" |
| get_file_content (anchor/range) | ≤5 calls | **Stop extracting.** Use snippets already fetched. Don't chase tangents |
| find_callers | ≤1 call | Don't re-call; use block_range from results |
| find_include_graph | ≤1 call | Don't re-call |

**Real-session lesson**: A UE material pipeline trace used 12 searches / 25 extracts (5x over cap) because "one more look" kept seeming justified. The extra calls added noise (Interchange plugins), not signal. The budget is the signal-to-noise boundary — beyond it, you're reading noise.

**Retry limits**: Each failure mode gets 1 retry max. After retry → output "not found" and move to next layer.

## FTS5 raw_query syntax

| Operator | Example |
|----------|---------|
| AND | `'"A" AND "B"'` |
| OR | `'"A" OR "B"'` |
| NOT | `'"A" NOT "B"'` |
| Column filter | `'file_path : "BasePass"'` |

Columns: `file_path`, `module_name`, `raw_content`. All terms ≥3 chars (trigram). NEAR/prefix not supported.

## Common failure patterns

| Pattern | Fix |
|---------|-----|
| Natural language query → 0 results | Use 2-3 symbol names, each ≥3 chars |
| Non-existent class name | Search broadly first, anchor on discovered names |
| Term too short (1-2 chars) | All terms ≥3 chars for trigram FTS5 |
| No expanded_terms on first search | Always pass class/symbol names |
| Guessed base class in anchor | `"class XXX : public"` without base |
| Guessed function name for execution flow | Use `find_callers` instead |
| Searched .cpp for class declaration | Class is in .h — search with `file_path :` filter |
| scope_filter was a dict (validation error) | Now accepts dict directly — no escaping needed. Prefer dict form. |
| module filter returned empty | Drop module param and retry |
| Repeated failed anchor | After **1 miss** → switch to block_range or different pattern. Do NOT try a 2nd anchor guess |
| >5 searches with no new signal | Stop. Output what was found and what remains unknown |
| First search flooded with plugin noise | Always include `module="Runtime"` or `module="Renderer"` to exclude Interchange/Plugin results |
| expanded_term returned 0 hits | The class name doesn't exist. Drop it, don't keep it. Replace with a discovered name |
| History pushes stale plugins to top | `history_refined` ranking can amplify noise from past sessions. Use `module` + `scope_filter` to override |
| `module="Engine"` returns empty for Runtime files | `Engine/Source/Runtime/*` files belong to `module="Runtime"`, NOT `"Engine"`. "Engine" is a directory name, not the MCP module name. Check the file path: `Engine/Source/Runtime/<ModuleName>/` → use that `ModuleName` |

## Two search modes: exact symbol vs exploratory

The filtering strategy depends on whether you're searching for a **known symbol name** or **exploring a concept**.

### Mode A: Exact symbol — `module` is everything, skip `scope_filter`

When the function/class name is already known, the symbol name itself provides near-perfect selectivity — only a handful of hits exist. The only filter that matters is `module`, and getting it wrong costs a wasted round-trip.

- **`module`**: Critical. Wrong module → 0 results. Derive it from the file path, not the top-level directory name. `Engine/Source/Runtime/Engine/...` → `module="Runtime"`.
- **`scope_filter`**: Useless. A unique function name already means "a function"; filtering by `block_type` adds zero signal.
- **`limit`**: Default 20 is more than enough.

### Mode B: Exploratory — `module` + `scope_filter` earn their keep

When searching a broad concept, results can number in the thousands. Here `module` narrows the haystack and `scope_filter` prunes by structural type (class vs function vs macro).

- **`module`**: Critical. Narrows from thousands to hundreds by excluding plugins.
- **`scope_filter`**: High value. Narrows from hundreds to tens by restricting to the relevant block type.
- **`raw_query` column filter**: Fallback when scope_filter errors.

### Decision rule

- **Known exact symbol name** → Mode A: `module` only, skip `scope_filter`
- **Concept/pattern exploration** → Mode B: `module` + `scope_filter`
- **Searching for a type definition** → Mode B: `scope_filter={"block_type":"class"}` is essential

## History signals: when they help and when they hurt

History boosts ranking of previously-clicked files. This is a **double-edged signal**:

| Scenario | Effect |
|----------|--------|
| Re-searching a known subsystem | ✅ Faster hit on already-discovered files |
| New search in an unexplored area | ✅ Neutral — FTS still dominates |
| Past session clicked noisy plugin files | ❌ Noisy results persist across sessions — `history_refined` keeps pushing them up |

**Countermeasure**: When `source: "history_refined"` appears on files you don't recognize (e.g., Interchange plugins), those are stale signals. Use `module` and `scope_filter` to aggressively narrow scope and drown them out.

## Verified token efficiency

| Approach | Calls | Tokens |
|----------|-------|--------|
| Full-file reads (~18 files) | ~18 | ~810,000 |
| Random unstructured search | ~30 | ~78,000 |
| Layer-first + bracket (target) | ~16 | ~10,000 |

- 34% of tool calls in unstructured sessions were avoidable failures
- scope_filter reduces noise by ~3K tokens/session
- Generic anchor `"class XXX : public"` has 100% success rate
