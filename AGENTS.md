# AGENTS.md

This repository provides a local MCP server for Unreal Engine source retrieval using **SQLite FTS5** (trigram tokenizer) with a **bracket skeleton structural index**.

## Architecture

One file = one row in `source_files`. FTS5 `snippet()` extracts relevant code fragments via a **two-step deferred query** (rank first, snippet only for top-N), so the agent never needs to read whole files for search results.

**Bracket skeleton index**: A 6-state FSM scans C/C++ source tracking brace pairs while ignoring braces in comments, strings, and raw string literals. Each brace pair records depth, open/close line, block type, and block name. This provides structural context without AST parsing — robust against macros and incomplete syntax.

**Include dependency graph**: O(1) basename hash lookup resolves 96.5% of include paths. Supports upstream/downstream traversal with configurable recursion depth.

**History-as-ranking-signal**: Past search feedback adjusts result ranking but never filters out results. This prevents confirmation bias while still accelerating relevant results.

### Query pipeline

```
search_source_with_feedback()
  ├── _search_fts()              # Two-step FTS5: rank → snippet for top-N only
  ├── _get_history_signals()     # Feedback scores (ranking, not filtering)
  ├── Composite scoring          # base_score + hist_bonus + discovery bonus
  ├── _apply_scope_filter()      # Bracket-based block_type/block_name filter
  └── _cluster_results()         # Merge hits in same code block
```

## Tools (5)

### 1. `search_unreal_source(query?, raw_query?, expanded_terms?, module?, limit?, cluster?, scope_filter?)`

FTS5 search with automatic history acceleration and structural features.

- **Simple mode** (`query`): literal text match. `"GetGBuffer"`, `"FMaterial Render"`
- **Advanced mode** (`raw_query`): raw FTS5 expression with AND/OR/NOT and column filters
- `expanded_terms`: domain-specific terms for history matching (e.g., `["FMaterial", "UMaterialInterface"]`)
- `module`: filter by UE module name (e.g., `"Renderer"`, `"UnrealEd"`, `"Niagara"`)
- `cluster`: merge multiple hits in the same code block into one result with `hit_count`
- `scope_filter`: JSON with `block_type` and/or `block_name` to restrict results (e.g., `'{"block_type": "function"}'`)
- Results include `source` field: `"history_refined"` or `"fts"`
- Results include `final_score`: composite of FTS5 rank + history bonus + discovery bonus

### 2. `get_file_content(file_path, start_line?, end_line?, anchor?, context_chars?)`

Read specific lines or anchor-based context. Two extraction modes:
- **Line range**: `start_line` / `end_line` — traditional line-based extraction
- **Anchor**: finds a string via `instr()` and extracts a window around it — avoids reading the whole file

Automatically records feedback when the file was in recent search results.

### 3. `log_unreal_query(query_text, was_useful?, refinement?)`

Record explicit feedback for a recent query. Use only to correct or supplement the automatic feedback from `get_file_content`.

### 4. `find_include_graph(file_path, direction?, depth?)`

Query include dependency relationships for a file.
- `direction`: `"upstream"` (who includes this file), `"downstream"` (what this file includes), or `"both"`
- `depth`: recursion depth (1 = direct dependencies only)
- Returns edges with source/target file paths and include paths

### 5. `find_callers(symbol, scope?)`

Find callers of a symbol using FTS5 text search + bracket skeleton structural context.
- Searches for the symbol in all indexed files
- Uses bracket_index to locate which function/class each occurrence belongs to
- Skips the definition block (where the symbol is the block name)
- `scope`: optional module name to limit search

## FTS5 Query Syntax (for raw_query)

| Operator | Syntax | Example |
|----------|--------|---------|
| AND | `"A" AND "B"` | `'"GetGBuffer" AND "Emissive"'` |
| OR | `"A" OR "B"` | `'"Lumen" OR "RayTracing"'` |
| NOT | `"A" NOT "B"` | `'"Material" NOT "hlsl"'` |
| Grouping | `("A" OR "B") AND "C"` | `'("alpha" OR "beta") AND "gamma"'` |
| Column filter | `column : "term"` | `'file_path : "BasePass"'` |

Columns: `file_path`, `module_name`, `raw_content`

**Rules:**
- All terms must be 3+ characters (trigram tokenizer requirement)
- Phrase queries use `"double quotes"`
- NEAR and prefix (`*`) operators do NOT work with trigram tokenizer
- Use `query` for simple lookups, `raw_query` when you need boolean logic or column-scoped search

## Block types (from bracket skeleton + symbol sniffer)

| block_type | Description | Example |
|------------|-------------|---------|
| `namespace` | Namespace block | `namespace MyEngine { ... }` |
| `class` | Class or struct | `class UMyClass : public UObject { ... }` |
| `enum` | Enum (plain or enum class) | `enum class ELightType { ... }` |
| `function` | Function/method | `void FRenderer::Render() { ... }` |
| `control_flow` | if/for/while/switch | `if (bEnabled) { ... }` |
| `macro` | Preprocessor #define | `#define IMPLEMENT_MODULE(...) { ... }` |
| `unknown` | Unrecognized block | Braces without matching pattern |

## Recommended flow

1. **Search**: `search_unreal_source` with keywords — returns snippets, not whole files.
2. **Drill down**: `get_file_content` with anchor mode or narrow line range if snippet context is insufficient (auto-feedback).
3. **Explore structure**: `find_include_graph` to understand file dependencies, `find_callers` to trace call sites.
4. **Correct feedback**: `log_unreal_query` only if you need to correct the automatic feedback.

## Guidance

- Avoid returning large file bodies — use `search_unreal_source` first.
- The feedback loop is automatic — no need to manually log unless correcting.
- Use `cluster=true` when searching common terms to reduce result noise.
- Use `scope_filter` to narrow results to specific block types (e.g., only functions).
- Use `anchor` mode in `get_file_content` for efficient single-symbol context — it's ~50x faster than reading the whole file.
- If the database has not been built yet, guide the user toward indexing first.
