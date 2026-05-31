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
| get_directory_structure | ~800 | First call — discover valid module names (compact: top 30 modules + 2-level dirs) |
| search_code_source (20 results) | 2,600 | Initial discovery |
| get_file_content (anchor, 500 chars) | 125 | **Always prefer** for single-symbol context |
| get_file_content (line range, 100 lines) | 900 | Need broader context |
| get_file_content (full file) | 45,000 | **BANNED** — never read full files |
| find_callers (specific symbol) | 127–3,000 | Trace call sites, **best anchor locator** |
| find_callers (common symbol) | ~27,000 | **Use `scope` to limit!** |
| find_include_graph (depth=1) | 50–2,100 | File dependencies |

## Tools (5)

### `get_directory_structure()`
Returns `modules` (name+count), `top_dirs` (path+count), `total_files`, `extensions`.

1. Merge/dedup semantically identical modules; mark false positives (e.g. "Private", "Public")
2. Write slim result to `ref/directory-structure.md`

**ref/directory-structure.md format:**
```markdown
# Directory Structure
total_files: N
## Valid modules (top 30)
- ModuleName (count)
## False positive modules
```

| Situation | Action |
|-----------|--------|
| `ref/directory-structure.md` missing | **Must call** → slim down → write ref |
| User asks to "check modules" / "refresh structure" | **Must call** → update ref |
| `module` filter returns empty | Read ref file to verify spelling |
| `ref/directory-structure.md` exists | Read ref file, skip API call |

### `search_code_source(query?, raw_query?, expanded_terms?, module?, limit?, cluster?, scope_filter?)`
FTS5 search with history-accelerated ranking (~2,600 tokens/20 results).
- Simple: `query="GetGBuffer"` / Advanced: `raw_query='"A" AND "B"'`
- `module`: filter by module name (from `get_directory_structure()`)
- `scope_filter`: **optional** post-filter — see scope_filter boundaries below
- `expanded_terms`: confirmed class/symbol names for history ranking boost (signal enrichment)
- Results **always include** block metadata (no need for cluster=true to get block info):
  - `block_type`: "function", "method", "class", "enum", etc.
  - `block_name`: e.g. "FShaderCache::GetShader"
  - `block_range`: e.g. "142-198"
- `cluster=true` additionally merges hits in the same block into one result with `hit_count`
- Results include `source` (history_refined or fts) and `final_score`

**`cluster=true` returns additional fields** (dedup + hit count):
```json
{
  "hit_count": 3,
  "cluster": {
    "block_type": "class",
    "block_name": "FVirtualTextureSystem",
    "open_line": 108,
    "close_line": 309
  }
}
```
Use `cluster.open_line/close_line` as `get_file_content(start_line, end_line)` anchors — no extra tool call needed.

### `get_file_content(file_path, start_line?, end_line?, anchor?, context_chars?)`
Read file via anchor (preferred) or line range. Auto-records feedback.
- anchor="Render", context_chars=500 → ~125 tokens
- start_line=100, end_line=200 → ~900 tokens
- **BANNED** without anchor or line range (full file ~45K tokens)
- If anchor unknown, use search_code_source block_range or find_callers caller_line, then use start_line/end_line
- Default context_chars=500~2000; class declarations usually 1000~2000

**Returns enclosing_block metadata** for the anchor/start_line position:
```json
{
  "enclosing_block": {
    "block_type": "function",
    "block_name": "MyClass::Tick",
    "block_range": "142-198",
    "signature": "void MyClass::Tick(float DeltaTime)"
  }
}
```

### `log_code_query(query_text, was_useful?, refinement?)`
Record explicit feedback. Auto-feedback is recorded by `get_file_content` anchor lookups, but has blind spots.

**When to call explicitly:**
- A search returned useful results but you skipped `get_file_content` (e.g., search results alone were sufficient) → `log_code_query(query_text, was_useful=true)`
- A search returned the wrong subsystem (e.g., "Texture" matched rendering textures instead of VT textures) → `log_code_query(query_text, was_useful=false, refinement="VirtualTexture")` to steer future ranking
- After a multi-layer exploration, log the final successful query for the key discovery step

### `find_include_graph(file_path, direction?, depth?)`
File-level #include dependency query. Complements find_callers (symbol-level refs).
direction: upstream / downstream / both. depth: recursion level.

### `find_callers(symbol, scope?, limit?)`
**Primary symbol reference tool** — two-phase search:

1. **Phase 1 (symbol_references)**: Query pre-computed reference table. Fast, block-type-aware,
   context-filtered (only tracks refs inside function/method/class/enum blocks).
   Result `source="symbol_references"` — **prefer these results**, they are precise.
2. **Phase 2 (FTS5 fallback)**: Runtime text search + bracket attribution. Only used when
   symbol has no pre-computed references. Result `source="fts5_fallback"`.

Supports fuzzy symbol resolution — e.g., "Actor" resolves to "AActor".

Each caller returns: `file_path`, `module_name`, `block_type`, `block_name`, `block_range`, `caller_line`.

- **Best anchor locator** — returns exact line numbers and block ranges
- Always use `scope` for common symbols (limits to a module)
- `scope`: module name — use `get_directory_structure()` or `ref/directory-structure.md` for valid values

## Bracket skeleton

### scope_filter — optional post-filter

**Accepts dict or JSON string:**

| Field | Valid values |
|-------|-------------|
| `block_type` | namespace / class / enum / function / control_flow / macro / unknown |
| `block_name` | Exact block name, case-insensitive |

`struct X` and `class X` are both `block_type="class"`.

**How it works:** `scope_filter` is a **post-filter** applied after FTS search. FTS returns `limit*5` results (e.g. 100 for limit=20), then scope_filter checks whether each result file has any matching depth=1 block, removing non-matches. It **cannot** add files that FTS missed — if the target file isn't in the expanded FTS result set (top-100), scope_filter won't help.

**When scope_filter is useful vs default block info:**

| Scenario | Recommended | Why |
|----------|------------|-----|
| Most searches | Default (no scope_filter) | Block info is always returned; preserves all FTS results |
| General word + too many irrelevant results | `scope_filter={"block_type":"class"}` | Post-filter narrows FTS results to files containing class blocks |
| Class definition discovery | `raw_query` file_path filter | More reliable than scope_filter |
| Need only results inside a specific class | `scope_filter={"block_name":"ClassName"}` | Only when FTS already includes the target file |

**Fallback when scope_filter fails**: Use `raw_query` column filter: `raw_query='(file_path : "MaterialShared") AND "FMaterial"'`

### Anchor construction

Use anchor from search result metadata:
- `block_range` (e.g. "142-198") → `get_file_content(start_line=142, end_line=198)` (preferred)
- `cluster.open_line/close_line` (when cluster=true) → same usage
- `enclosing_block.signature` → `get_file_content(anchor="void MyClass::Tick")`
- `find_callers` result → `get_file_content(start_line=caller_line-5, end_line=caller_line+30)`

## Tool decision matrix

| Sub-problem | Primary tool | Notes |
|------------|-------------|-------|
| Known exact symbol | search(`query`) | block info always included |
| Known exact symbol + callers | find_callers(symbol, scope=...) | **Best anchor locator** — pre-computed refs with FTS5 fallback |
| Concept/pattern exploration | search(`query`, module=...) | Observe module_name + block_type distribution first |
| Type definition | search(`raw_query` file_path filter) | `(file_path : "Header.h") AND "ClassName"` |
| Call chain (who calls X?) | find_callers(symbol, scope=...) | NOT for data flow or class hierarchies |
| File dependencies | find_include_graph | — |

### module ownership confirmation

**First exploratory search in Phase 1C doubles as module ownership check** — observe `module_name` field distribution in the results, then use `module` filter for subsequent targeted searches in Phase 3C/4.

## Abstraction Frame + Search Pipeline

### Abstraction Frame — describe the target system's architecture

**Before any tool call**, plan an Abstraction Frame describing the target system's architectural layers:

```
ABSTRACTION FRAME (for "<user intent>"):
  Layer 1: [name] — <role in the system>
  Layer 2: [name] — <role in the system>
  ...
```

Each Layer describes **one architectural slice of the target system**, NOT a search step. Example:

```
ABSTRACTION FRAME (for "VT系统架构分析"):
  Layer 1: [Core Abstractions] — IVirtualTexture, IAllocatedVirtualTexture 等公共接口
  Layer 2: [Central Coordinator] — FVirtualTextureSystem 单例及其更新管线
  Layer 3: [Virtual Memory] — FVirtualTextureSpace, PageTable 地址空间
  Layer 4: [Physical Storage] — FVirtualTexturePhysicalSpace, TexturePagePool 物理页管理
  Layer 5: [Data Producers] — FVirtualTextureProducer, SVT/RVT 两种模式
```

### Search Pipeline — tool execution order (iterates per Layer)

The pipeline runs **per Architecture Layer**, moving to the next Layer when the current one is sufficiently understood.

```
Phase 1: LOCATE — find anchors
  1A. Known exact class → search(query="ClassName")
      → block_range = free anchor
  1B. Known symbol to trace → find_callers(symbol, scope=module)
      → caller_line + block_range = line-level anchor
      → source="symbol_references" (pre-computed) or source="fts5_fallback"
  1C. Exploratory → search(query="keyword")
      → observe module_name distribution + block_type/block_name

Phase 2: READ — extract anchor content
  2A. Have block_range → get_file_content(start_line, end_line)
      → enclosing_block provides signature + block metadata
  2B. Have anchor word → get_file_content(anchor="class XXX : public")
  2C. Have find_callers caller_line → get_file_content(start_line=caller_line-5, end_line=caller_line+30)

Phase 3: TRACE — follow relationships
  3A. Call chain → find_callers(symbol, scope=module)
  3B. Dependency graph → find_include_graph(file_path)
  3C. Supplementary search → search(query + expanded_terms + module)

Phase 4: ENRICH — fill gaps
  search(expanded_terms=confirmed class names from Phase 1-3)

Phase 5: CLOSE — wrap up
  log_code_query
```

### Budget hard limits

| Resource | Cap |
|----------|-----|
| Architecture Layers | 6 max |
| search_code_source | ≤6 calls |
| get_file_content (anchor/range) | ≤8 calls |
| find_callers | ≤5 calls |
| find_include_graph | ≤3 calls |

Each failure mode gets 1 retry max. After retry → "not found", move to next phase/layer.

## Signal enrichment

`expanded_terms` boosts history_refined ranking for known class names. This is **signal enrichment** (ranking acceleration), NOT intent expansion.

On first search of a new subsystem, pass `expanded_terms` with estimated class/symbol names:
- "Material architecture" → `["FMaterial","UMaterialInterface","MaterialResource"]` (substitute actual project class names)
- Estimates don't need to be exact — history_refined uses them for ranking boost, not filtering
- After first search, replace any names that returned 0 hits with confirmed names from results

### Progressive signal enrichment

**expanded_terms must be updated across successive searches within the same subsystem exploration.**

1. **First search** — use estimated class names based on domain knowledge (some may not exist, that's expected)
2. **After first search** — collect confirmed class/file names from results, drop non-existent terms
3. **Subsequent searches** — pass updated expanded_terms with only confirmed names from prior phases

Example progression for a VT subsystem exploration:
- Search 1: `expanded_terms=["UVirtualTexture","FVirtualTexture","IVirtualTexture","FVirtualTextureSystem"]` (estimated)
- Search 2: `expanded_terms=["UVirtualTexture2D","FVirtualTextureSpace","FAllocatedVirtualTexture"]` (confirmed from search 1 results)
- Search 3: `expanded_terms=["FVirtualTexturePhysicalSpace","TexturePagePool","FVirtualTextureProducer"]` (confirmed from search 1–2)

**Why:** history_refined ranking only fires when expanded_terms match past query logs. Reusing stale or skipping expanded_terms on later searches wastes the history acceleration, forcing pure FTS5 ranking.

## FTS5 raw_query syntax

| Operator | Example |
|----------|---------|
| AND | `'"A" AND "B"'` |
| OR | `'"A" OR "B"'` |
| NOT | `'"A" NOT "B"'` |
| Column filter | `'file_path : "BasePass"'` or `(module_name : "Runtime")` |

Columns: `file_path`, `module_name`, `raw_content`. All terms ≥3 chars (trigram). NEAR/prefix not supported.

## Parameter compatibility

| Combination | Works | Notes |
|-------------|-------|-------|
| query + module | ✓ | Independent AND filters |
| query + module + expanded_terms | ✓ | All three coexist |
| raw_query + module | ✓ | Column filter + module |
| raw_query + module + expanded_terms | ✓ | All three coexist |
| cluster=true + any search | ✓ | Merges hits in same block, adds hit_count |
| scope_filter + query | ⚠ | Only when FTS already hits target file |
| scope_filter + module | ⚠ | May over-narrow |

## Common failure patterns

| Pattern | Fix |
|---------|-----|
| Natural language query → 0 results | Use 2-3 symbol names, each ≥3 chars |
| Term too short | All terms ≥3 chars for trigram FTS5 |
| Guessed base class in anchor | `"class XXX : public"` without base |
| Guessed function name for flow | Use `find_callers` instead |
| Searched .cpp for class declaration | Class is in .h — search with `file_path :` filter |
| scope_filter returns 0 | **FTS didn't hit target file** — use `raw_query` file_path filter instead |
| module filter returns empty | Drop module param and retry (bare search first to confirm ownership) |
| Repeated failed anchor | After 1 miss → switch to block_range. Do NOT retry anchor |
| Full file read attempted | **BANNED** — must use anchor or start_line/end_line |
| >5 searches with no new signal | Stop. Output what was found and what remains unknown |
| expanded_term returned 0 hits | Class name doesn't exist. Drop it, replace with discovered name |
| history_refined pushes stale results | Use `module` + `raw_query` file_path to override |
| scope_filter + query returns empty | scope_filter is a post-filter — FTS result must contain target file. Use `raw_query` file_path or default search instead |

### scope_filter + query must agree

**Core rule: `scope_filter` is a post-filter on FTS results. It checks if the file has a matching depth=1 block. The FTS query must already return the target file, or scope_filter cannot help.**

When using scope_filter, keep query to a single precise symbol:

| Goal | Correct | Wrong |
|------|---------|-------|
| Find class IVirtualTexture | `query="IVirtualTexture"`, `scope_filter={"block_type":"class"}` | `query="IVirtualTexture Producer"`, `scope_filter={"block_type":"class"}` |
| Find FMaterial::Render method | `query="Render"`, `scope_filter={"block_type":"function","block_name":"FMaterial"}` | `query="FMaterial Render shader"`, `scope_filter={"block_type":"function"}` |

**Better alternative for most cases:** Use default search (no scope_filter) — block info is always returned without filtering, preserving all FTS results.
