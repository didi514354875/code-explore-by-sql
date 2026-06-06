---
name: code-source-sql-search
description: "Use when: source code lookup with code-source-sql MCP tools, qualified-symbol lookup, search_fts_tool grep-style discovery, read_symbol navigation, read_file_range location-based reading, macro/delegate/routing inspection, or directory/module lookup."
argument-hint: "Describe the symbol, qualified name, macro, binding, subsystem, or behavior to locate."
user-invocable: true
disable-model-invocation: false
---

# Code Source SQL Search

Use the **`code-source-sql` MCP tools** for source code lookup.

## Multi-database

The server can access multiple databases. Each tool accepts an optional `db` parameter (database alias).

- **`list_databases()`** — discover available databases and their aliases.
- `db=""` (default) → primary database (`CODE_SOURCE_DB`).
- `db="mygame"` → database whose filename stem is `mygame` (e.g. `mygame.db`).
- Unknown alias → silently falls back to primary database.

Use `list_databases` first to see what's available, then pass the `alias` as `db` to other tools.

## Database Setup

If `list_databases` returns empty, or any tool returns a database-not-found / no-such-table error, the database needs to be built first.

**Build command** (run in terminal, not via MCP):

```bash
code-explore-by-sql-build-db /path/to/source_code /path/to/output.db [--limit N]
```

- `/path/to/source_code` — root directory of the codebase to index
- `/path/to/output.db` — output SQLite database file (created automatically)
- `--limit N` — optional: index only the first N files (smoke test)

After building, update the MCP server config (`CODE_SOURCE_DB` env var) to point to the new `.db` file, then restart the MCP server.

**Agent behavior:** When tools fail due to missing database, ask the user for the source code path and desired output path, then provide the exact `code-explore-by-sql-build-db` command for them to run.

## Tool surface

### `list_databases()`

Discover — list available databases with stats.

Returns `{default, databases: [{alias, path, total_files?, total_symbols?, error?}]}`.

Use before any other tool when multiple databases are configured.

### `search_fts_tool(keyword="", path_filter="", expand_item=None, raw_query="", db="")`

**Locate** — find code blocks, return file location and enclosing symbol.

Two query modes (mutually exclusive — use one):

| Mode | Param | When | Example |
|------|-------|------|---------|
| Simple | `keyword` | Quick search, one or two tokens | `"AddDynamic"` |
| Advanced | `raw_query` | Column filter, OR/NOT, file narrowing | `'(file_path : "Character.h") AND "BeginPlay"'` |

- `keyword`: auto-escaped AND of tokens. Safe, no syntax errors.
- `raw_query`: full FTS5 MATCH expression. Agent controls the query.

Each result: `file`, `line`.
If enclosing block found: `block` (QN), `block_type`.
No code — use `read_symbol` or `read_file_range` to fetch code.
No results → `[]`. Malformed raw_query → `[]` (no crash).

**FTS5 raw_query syntax:**

```
Columns: file_path, module_name, content (all trigram, ≥3 chars per term)

Operators:
  AND  →  '"AddDynamic" AND "UObject"'
  OR   →  '"AActor" OR "APawn"'
  NOT  →  '"Update" NOT "Component"'
  Column filter →  '(file_path : "Character.h") AND "BeginPlay"'

Examples:
  '("Server" OR "Client") AND "EquipWeapon"'           # RPC discovery
  '(file_path : "Shader.h") AND "FShaderType"'         # Pin to known file
  '(module_name : "Renderer") AND "VirtualTexture"'    # Module-scoped
  '"AddDynamic" NOT "Test"'                            # Exclude test files
```

Rules:
- Search concrete code tokens, not natural language
- `path_filter` narrows by module_name (simple mode only). For file_path filtering, use `raw_query` column filter instead.

### `read_symbol(qualified_name, view="full", expand_item=None, db="")`

**Read by name** — get full code. **Only use after `search_fts_tool` provides a block QN.**

- Exact or fuzzy match (`Jump` matches `ACharacter::Jump`)
- Returns `{qn, type, file, range, code?}`
  - `view="full"`: complete code
  - `view="signature"`: signature summary (≤80 lines)
  - `view="meta"`: identity only, no code
- Multiple matches: `alt` list (max 4, no code)
- Not found → `{error: "not_found", query, fts?}`

### `read_file_range(file_path, start_line, end_line, view="full", expand_item=None, db="")`

**Read by position** — get code. **Only use after `search_fts_tool` provides file+line.**

- Returns `{file, range, code?, symbols?}`
- `symbols` lists all symbols in range as `{qn, type, range}`
- Not found → `{error: "not_found", file}`

### `get_directory_structure(db="")`

Module overview. Returns `{total_files, total_modules, modules: [{module_name, file_count}]}`.

Use to discover module names for `(module_name : "...")` column filter in raw_query.

## Abstraction Frame

Before any code lookup, state an Abstraction Frame for the user's intent. The frame describes architectural slices of the target system — it is **not** a search plan. Each layer represents one system role.

Format (2-6 layers; narrow lookups need fewer):

```text
ABSTRACTION FRAME (for "<user intent>"):
  Layer 1: [Core Abstraction] — public interfaces, base types, key symbols
  Layer 2: [Entry Points] — central manager, lifecycle, dispatch
  Layer 3: [State / Storage] — registries, cached state, ownership
  Layer 4: [Execution Flow] — implementations and static call chains
  Layer 5: [Glue] — macros, callbacks, bindings, generated routing
  Layer 6: [Boundaries] — modules, platform/subsystem seams
```
## Signal enrichment

`expand_item` is **ranking acceleration** for tool calls — it annotates and prioritizes results when multiple candidates match. It is **not** intent expansion and must never substitute for the actual query.

**Working set** — maintain a compact set of confirmed signals:

| Signal type | Examples |
|-------------|---------|
| Qualified names | `ClassName::MethodName` or `ClassName.MethodName`|
| Owning types | parent class, component type |
| Routing variants | `_Implementation`, `_Validate` |
| Framework metadata | macro specifiers, routing annotations |
| Glue terms | delegate names, callback names, binding macros |
| Module/path | from `search_fts_tool` or `get_directory_structure` |

**Usage:**

- Pass as `expand_item` to any tool call to rank ambiguous results.
- Refresh after every read: add confirmed dependencies, drop unresolved guesses.
- Use to construct the next precise `read_symbol` qualified name or choose narrower `search_fts_tool` keywords.

**Anti-patterns:**

- Bad: `search_fts_tool("Update", expand_item=["everything related"])` without a receiver type.
- Bad: Using `expand_item` as the actual query instead of `qualified_name` / `keyword`.

## Three-level funnel

**Always start with `search_fts_tool`.** Every lookup enters the funnel at Level 1.

```
Level 1: search_fts_tool(keyword) → file_path candidates + block QNs
Level 2: search_fts_tool(raw_query, file_path filter) → precise block in target file
Level 3: read_symbol(block QN) or read_file_range(file, line) → full code
```

| Level | Tool | Input | Output | What narrows |
|-------|------|-------|--------|-------------|
| 1 | `search_fts_tool` keyword | keyword | file_path candidates + block QNs | all files → ~30 hits |
| 2 | `search_fts_tool` raw_query | file_path from L1 + new token | precise block in specific file | ~30 hits → ~5 hits in target file |
| 3 | `read_symbol` / `read_file_range` | QN from L1/L2 or file+line from L1/L2 | full code | exact code block |

**Iron rules:**

1. **Always start with `search_fts_tool`.** No tool call before it. Even with a known QN, search first to get file_path and preview.
2. **Stop when preview suffices.** If `search_fts_tool` returns enough code/signature, done — no `read_symbol` needed.
3. **`read_symbol` / `read_file_range` only use data from `search_fts_tool`.** Block QN, file, and line all come from search results. Never guess or assume.

## Tool selection by intent

| Intent | Level 1 | Level 2 if needed | Level 3 if needed |
|--------|---------|-------------------|-------------------|
| Any symbol | `search_fts_tool` keyword | `search_fts_tool` raw_query file_path filter | `read_symbol` (block QN) |
| Glue / delegate | `search_fts_tool` keyword | Usually preview is enough | — |
| Narrow to file | `search_fts_tool` keyword → then raw_query | file_path column filter | `read_symbol` |
| Browse large class | `search_fts_tool` keyword → get class block QN | `read_symbol` view="signature" | `read_symbol` view="full" on methods |
| Code outside symbols | `search_fts_tool` keyword → get file+line | — | `read_file_range` |

## Trace rules

After reading code in Level 3:
- static call → `search_fts_tool(keyword="CalledFunction")` to locate, then `read_symbol` with block QN
- delegate binding → `search_fts_tool(keyword="BoundFunctionName")` to locate
- On seeing `Obj->Update()`, never blindly search `Update`. Infer receiver type first, then `search_fts_tool(keyword="Type::Update")`.
- Avoid Cartesian explosion: only follow deterministic static relations.

## Failure handling

| Failure | Response |
|---------|----------|
| Database not found / empty `list_databases` | See **Database Setup** section — provide `code-explore-by-sql-build-db` command |
| `search_fts_tool` no results | Retry with different token or raw_query OR |
| `search_fts_tool` too broad | Narrow with raw_query file_path column filter |
| `read_symbol` miss (after search gave block QN) | `read_file_range` with file+line from search result |
| `read_symbol` wrong definition | `read_file_range` with file+line from search result |
| Pointer call target unknown | Read current code, infer receiver type, then `search_fts_tool` |
| Large symbol (>100 lines) | `read_symbol` view="signature" first |
| >5 searches with no new signal | Stop and report knowns/unknowns |

## Budget limits

| Resource | Cap |
|----------|-----|
| `search_fts_tool` | ≤6 |
| `read_symbol` | ≤8 |
| `read_file_range` | ≤4 |
| `get_directory_structure` | ≤1 |

## Output requirements

- Cite file paths and symbols with backticks
- Separate confirmed facts from inferences
- When not found, list queries attempted and recommended next step
