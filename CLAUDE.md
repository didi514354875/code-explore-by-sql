# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
uv sync --dev

# Run all tests
uv run pytest

# Run a single test file
uv run pytest tests/test_bracket_scanner.py

# Lint
uv run ruff check .
uv run ruff format .

# Build the source index (requires a source tree to index)
uv run python -m code_source_sql.build_db /path/to/source /path/to/db.db --limit 100

# Run the MCP server
CODE_SOURCE_DB=/path/to/db.db uv run code-source-sql
```

## Architecture

Local stdio MCP server for source code navigation using **SQLite FTS5** (trigram tokenizer) + **bracket skeleton indexing**. No AST parser — uses heuristic regex and FSM-based brace matching. The active package is `src/code_source_sql/` (`code_explore_by_sql` is a legacy implementation, not used).

### Layered Configuration System

All language/framework/project behavior is driven by three frozen dataclasses in `configs.py`:

- **`LanguageConfig`** — Syntax rules selected by file extension. Factory functions: `make_cpp_language()`, `make_csharp_language()`. Controls regexes for class/enum/namespace/function detection, edge extraction patterns, bracket scanner hints (e.g., C# verbatim strings), block classification, and view/summary formatting.
- **`FrameworkConfig`** — Application framework rules overlaid on any language. Holds both data fields (regexes, skip types) and **behavior callbacks** for framework-specific algorithm logic. `make_unreal_framework()` (UE macros, RPC routing, skip types) and `make_generic_framework()` (no-op). Lives in `unreal_rules.py`.
- **`ProjectConfig`** — User settings: file extensions → language mapping, exclude dirs, module inference rules.

The layering is: Language × Framework → per-file config. `build_db._get_configs()` dispatches by extension: C++ files in Unreal projects get Unreal framework; C# files always get generic framework (UE C++ rules don't apply to C#).

### Processing Pipeline (per file)

`build_db._process_file()` orchestrates:
1. `bracket_scanner.scan_brackets()` — 6-state FSM (CODE, LINE_COMMENT, BLOCK_COMMENT, STRING, CHAR_LITERAL, RAW_STRING, VERBATIM_STRING) finds brace pairs with depth info. Accepts `verbatim_string_prefix` for C# `@"..."` support.
2. `symbol_analyzer.analyze_file()` — Classifies blocks into `SymbolDef`/`ExtraSymbol` with QN normalization. Always uses `::` as internal QN separator regardless of language. Sniffs framework decoration macros (UCLASS, UFUNCTION) above blocks via `fw.sniff_decoration_above` / `fw.decoration_macro_re`. Delegates delegate-name parsing and macro filtering to `fw.parse_delegate_name` and `fw.macro_name_filter` callbacks.
3. `edge_extractor.extract_edges()` — Extracts 4 deterministic edge types: inheritance, type_dependency, static_call, rpc_routing. Skip types come from `LanguageConfig.basic_skip_types` + `FrameworkConfig.skip_types` + `noise_type_names`. RPC routing is delegated to `fw.extract_framework_edges` callback.
4. Writes to SQLite via `db.py`.

### Database Schema (3 tables)

- `file_content` + FTS5 trigram index — raw source with full-text search
- `symbol_index` — qualified names, block types, decoration metadata, line ranges, language
- `strict_edges` — 4 edge types between symbols

### MCP Server Tools (4 tools in `server.py`)

| Tool | Purpose |
|------|---------|
| `read_symbol` | Precise QN lookup with [System Hint] header (edges, decoration metadata) |
| `search_fts_tool` | FTS5 grep-style search with context lines |
| `read_file_range` | File range read with symbol metadata overlay |
| `get_directory_structure` | Module/file counts from index |

### Code Block Summary (`code_block_summary.py`)

`apply_view()` provides three views: `full` (raw code), `signature` (summarized — class signatures, function bodies reduced to local vars + control flow), `meta` (header only). All strategies accept `lang`/`fw` kwargs from the layered config system.

### Key Module Interactions

```
server.py  →  db.py  →  code_block_summary.py  (view formatting)
                        configs.py              (LanguageConfig/FrameworkConfig)
build_db.py → bracket_scanner.py → symbol_analyzer.py → edge_extractor.py
               configs.py           configs.py            configs.py
               unreal_rules.py      unreal_rules.py       unreal_rules.py
                                    ↑                     ↑
                                    │ callback            │ callback
                                    │ (parse_delegate,    │ (extract_framework_edges,
                                    │  macro_filter)      │  format_meta_display)
                                    └───── unreal_rules.py ─────┘
```

## Architecture Principles

These principles govern all code in `code_source_sql/`. When adding or modifying code, follow them strictly.

### 1. Algorithm code is language-agnostic; specifics come from config

All core processing modules (`bracket_scanner`, `symbol_analyzer`, `edge_extractor`, `code_block_summary`) must be **generic** — they contain no language-specific constants, regexes, or hardcoded syntax. Every language-dependent behavior (regex patterns, skip types, scope operators, keyword sets) is injected via `LanguageConfig` or `FrameworkConfig` parameters.

**Wrong**: Hardcoding `"::"` as separator, `"public:"` as access specifier, or `r"\bnamespace\b"` as a keyword pattern inside algorithm code.

**Right**: Reading `lang.scope_operator`, `lang.access_spec_names`, `lang.block_keyword_re` from the `LanguageConfig` passed as a parameter.

### 2. Three-layer lookup: Extension → Language → Framework

The dispatch chain is:
1. **File extension** → `ProjectConfig.extension_to_language` maps it to a language name (e.g., `".cs"` → `"csharp"`)
2. **Language name** → factory function creates `LanguageConfig` (e.g., `make_csharp_language()`)
3. **Language + Framework** → `build_db._get_configs()` combines them (e.g., C# always gets generic framework in Unreal projects)

Any new language support means: add a `make_xxx_language()` factory in `configs.py` and register the extensions in `ProjectConfig`. No algorithm module changes needed.

### 3. No hardcoded language syntax in processing modules

Specific prohibitions in `bracket_scanner.py`, `symbol_analyzer.py`, `edge_extractor.py`, `code_block_summary.py`:
- No hardcoded scope operators (`::`, `.`) — use `lang.scope_operator`
- No hardcoded access specifiers (`"public:"`, `"private:"`) — use `lang.access_spec_names`
- No hardcoded block keywords (`namespace`, `class`, `struct`) — use `lang.block_keyword_re`
- No hardcoded skip types (`int`, `bool`, `TArray`) — use `lang.basic_skip_types | fw.skip_types`
- No hardcoded control flow names (`if`, `for`, `while`) — use `lang.control_flow_names`
- No hardcoded string syntax assumptions — use `lang.verbatim_string_prefix`, `lang.lambda_re`, etc.

### 4. QN internal format is language-independent

Internal qualified names always use `::` as separator (e.g., `ACharacter::Jump`, `System.IO.File::ReadAllText`). The `scope_operator` field (`.` for C#, `::` for C++) is only used for **source text regex matching**, never for QN assembly. This means QN construction in `edge_extractor` and `symbol_analyzer` uses `::` unconditionally — the `scope_operator` value never appears in a QN string.

### 5. Framework-specific algorithm logic lives in callbacks on FrameworkConfig

Framework-specific ALGORITHMS (not just data) must be extracted to callable fields on `FrameworkConfig`. Processing modules call `fw.some_callback(...)` instead of implementing framework-specific branching/looping logic inline.

Current callbacks on `FrameworkConfig`:
- `extract_framework_edges(qn, decoration_meta)` → `[(target_qn, edge_type)]` — RPC routing and similar implicit edges
- `parse_delegate_name(stripped_line)` → `str | None` — delegate/type name from declaration macros
- `macro_name_filter(name)` → `bool` — skip noise macro definitions
- `format_meta_display(meta)` → `[str]` — decorate metadata display output
- `resolve_type_prefixes(qualified_name)` → `[str]` — generate candidate QNs with type prefixes

**Wrong**: Implementing RPC routing logic, delegate name parsing, or GENERATED_ macro filtering inline in `edge_extractor.py` or `symbol_analyzer.py`.

**Right**: These algorithms live in standalone functions in `unreal_rules.py` and are wired into `FrameworkConfig` via callbacks. The generic framework (`make_generic_framework()`) sets them to `None`, making the processing modules truly framework-agnostic.

## Key Conventions

- **Trigram FTS5**: Search terms must be 3+ characters. The `search_fts_tool` auto-escapes queries.
- **Bracket scanner is heuristic**: Not an AST — robust against macros but has no type information.
- **Frozen dataclasses**: All config objects are immutable. Factory functions create them.
- **Python ≥3.10**: Uses `X | Y` union syntax, `match` is available but not used.
- **DB environment variable**: `CODE_SOURCE_DB` points to the SQLite database path (set in `.mcp.json`).
