# Architecture Design Reference

## Overview

unreal-source-mcp is a local MCP server that provides fast structural code navigation for Unreal Engine source (~85K files, 2.5 GB) without requiring an AST parser or compiler toolchain. It combines SQLite FTS5 full-text search with a lightweight **bracket skeleton index** for structural context.

## Design Principles

1. **No AST dependency** — bracket skeleton indexing is robust against macros, incomplete syntax, and missing headers
2. **Read-heavy optimization** — search queries are optimized for latency; indexing is batch-oriented
3. **History as ranking, not filtering** — past feedback adjusts scores but never removes results (prevents confirmation bias)
4. **Two-step query execution** — rank with bm25 first, compute expensive snippets only for top-N results
5. **O(1) include matching** — pre-built basename hash map eliminates per-include LIKE scans

---

## Core Components

### 1. Bracket Scanner (`bracket_scanner.py`)

A 6-state finite state machine that tracks brace depth while correctly ignoring braces in:
- Line comments (`//`)
- Block comments (`/* ... */`)
- String literals (`"..."`)
- Character literals (`'...'`)
- Raw string literals (`R"delim(...)delim"`)

**States**: `CODE → LINE_COMMENT → BLOCK_COMMENT → STRING → CHAR_LITERAL → RAW_STRING`

Output: `list[BracketBlock]` where each block records:
- `open_line` / `close_line` — 1-based line numbers
- `depth` — nesting level (1 = top-level)
- `is_complete` — whether a matching `}` was found

**Optimization: Line-level fast skip**
Lines without any trigger characters (`{}"/'R`) are skipped entirely in CODE state. This saves ~60-70% of line iterations.

**Optimization: No-brace files**
Files without `{` skip bracket scanning entirely; only `#include` parsing runs.

### 2. Symbol Sniffer (`symbol_sniffer.py`)

Classifies top-level blocks (depth=1) by examining the preceding lines using heuristic regex patterns:

| Priority | Type | Detection |
|----------|------|-----------|
| 0 (highest) | `macro` | `#define` prefix match |
| 1 | `namespace` | `\bnamespace\s+(\w+)` |
| 2 | `enum` | `\benum\s+(class\s+)?(\w+)` |
| 3 | `class` | `\b(class\|struct)\s+...(\w+)` |
| 4 | `function` | Ends with `)`, not control flow |
| 5 | `control_flow` | `\b(if\|else\|while\|for\|do\|switch\|catch\|try)\b` |
| 6 | `unknown` | No pattern matched |

**UE macro skip**: Lines matching UE macros (UCLASS, USTRUCT, UPROPERTY, UFUNCTION, GENERATED_BODY, etc.) are filtered before pattern matching.

**Same-line handling**: Text on the `{` line itself (e.g., `namespace NS {`) is included in the context.

### 3. FTS5 Search Pipeline (`db.py`)

```
search_source_with_feedback()
  │
  ├── Step 1: _search_fts()  — Two-step FTS5 query
  │     ├── Step 1a: bm25() + ORDER BY + LIMIT → top-N rowids
  │     ├── Step 1b: Module filter via JOIN on candidates (if module set)
  │     └── Step 1c: snippet() only for final top-N
  │
  ├── Step 2: _get_history_signals()  — Past feedback scores
  │     └── query_logs_fts MATCH terms → file_id → weighted score
  │         with 30-day half-life time decay
  │
  ├── Step 3: Composite scoring (in-memory)
  │     final_score = base_score + hist_bonus + discovery_bonus
  │     base_score  = clamp(-rank / 2, 0, 10)
  │     hist_bonus  = clamp(history_score, -3, 5)
  │     discovery   = 1.0 if no history and base_score > 3
  │
  ├── Step 4: _apply_scope_filter()  — Bracket-based filtering
  │     └── For each result, load bracket_index depth=1
  │         → keep only if any block matches block_type/block_name
  │
  ├── Step 5: _cluster_results()  — Optional merging
  │     └── Group by (file_id, top_block_open_line)
  │         → merge into one result with hit_count
  │
  └── Step 6: log_query()  — Record for future history
```

### 4. Include Dependency Graph (`db.py`)

**Path matching strategy:**

During indexing, a pre-built lookup maps file basename → file_id:
- **Unique basenames** (96.5%): `basename → file_id` — O(1)
- **Ambiguous basenames** (3.5%): `basename → [(file_id, path), ...]` — O(k) suffix match

This replaces the original per-include `LIKE '%path%'` query (O(N) per include) with O(1) hash lookup.

**Graph traversal:**
- `find_include_graph(direction, depth)` uses recursive CTE-style traversal
- Visited-set prevents infinite loops on circular includes

### 5. Caller Lookup (`server.py`)

```
find_callers(symbol, scope?)
  ├── search_source(symbol, limit=50)     # FTS5 find occurrences
  │
  └── For each result file:
        ├── load_bracket_index(file_id, depth=1)  # Get top-level blocks
        └── For each block:
              ├── Skip if block_name matches symbol (definition)
              └── Record as caller with block_type, block_name, range
```

---

## Database Schema

```sql
-- File storage + FTS5 content
source_files (id, file_path, module_name, raw_content, content_hash, updated_at)
source_files_fts (FTS5 trigram on file_path, module_name, raw_content)

-- Bracket skeleton
bracket_index (id, file_id, open_line, close_line, depth,
               block_type, block_name, signature, is_complete)
  INDEX idx_bracket_file_depth ON (file_id, depth)
  INDEX idx_bracket_file_open  ON (file_id, open_line)

-- Include dependencies
include_edges (id, source_file_id, include_path, target_file_id, line_number)
  INDEX idx_include_source ON (source_file_id)
  INDEX idx_include_target ON (target_file_id)

-- Search feedback loop
query_logs (id, query_text, fts_match, hit_file_ids, hit_count, created_at)
query_logs_fts (FTS5 trigram on query_text, fts_match)
query_note (id, query_log_id, adopted_file_id, was_useful, refinement, note)
```

---

## Indexing Pipeline

```
build_index(root, db_path)
  │
  ├── Phase 1: Fast file import (skip_structural=True)
  │     iter_source_files() → for each file:
  │       upsert_source_file(skip_structural=True)
  │       commit every 500 files
  │
  └── Phase 2: Parallel structural indexing
        backfill_structural_index(conn, workers=auto)
          ├── _build_path_lookup() → (unique_map, collision_map)
          ├── DELETE bracket_index + include_edges
          └── For each batch of 500 files:
                ├── Single-process if ≤ 2 cores
                ├── Multi-process Pool.map if ≥ 4 cores
                │     _scan_file_worker(file_id, content, maps)
                │       ├── No-brace fast path (3.3% of files)
                │       ├── scan_brackets(content, lines)
                │       ├── sniff_blocks_for_file(lines, top_blocks)
                │       └── _build_include_edges(lines, maps)
                └── executemany INSERT bracket_index + include_edges
```

**Module name inference:**
- Paths under `Source/{Category}/{Module}/...` → returns `{Module}`
- Category directories (Runtime, Editor, Developer, Programs, Games, Plugins) are skipped
- Paths under `Source/{Module}/...` → returns `{Module}`

---

## Performance Characteristics

Tested on 84,696 Unreal Engine source files (2.5 GB database), 2-core machine.

### Query latency

| Operation | Latency | Notes |
|-----------|---------|-------|
| Single keyword (Render, 11K matches) | 88 ms | Two-step FTS5 |
| Full pipeline (FTS5 + history + scoring) | 115 ms | Best=108ms |
| Module-filtered search | 246 ms | JOIN on candidates, not subquery |
| 10-query rapid-fire average | 501 ms | Mix of common/rare terms |
| find_callers (Render) | 107 ms | 285 callers found |
| find_include_graph (depth=1) | 15 ms | Per file |
| Bracket index load (depth=1) | 0.9 ms | Per file |
| Anchor content extraction | 0.1 ms | instr + substr |
| History signal computation | 0.3 ms | FTS5 on query_logs |

### Indexing throughput

| Metric | Value |
|--------|-------|
| Total files | 84,696 |
| Phase 1 (import) | ~30s |
| Phase 2 (structural) | ~3 min (single process, 2 cores) |
| Bracket blocks created | 2,486,817 |
| Include edges created | 509,203 (95.2% matched) |
| Incomplete blocks | 0.01% |

### Optimization history

| Optimization | Before → After | Speedup |
|-------------|----------------|---------|
| Two-step FTS5 (defer snippet) | 9,600ms → 88ms | 109x |
| Module filter (JOIN vs subquery) | 35,800ms → 246ms | 145x |
| Include matching (hash vs LIKE) | O(N) per include → O(1) | ~100,000x |
| Multi-process scanning | 19.3min → 3.3min | 5.8x |
| No-brace file skip | Skips 3.3% of files entirely | ~3% |
| Line-level fast skip | Skips ~60-70% of lines in CODE state | ~2x on scanner |

---

## Limitations and Design Trade-offs

1. **Symbol sniffer is heuristic** — complex C++ patterns (CRTP, SFINAE, variadic templates) may classify as `unknown`. This is acceptable: the structural context is still useful even if the type label is imperfect.

2. **Bracket skeleton ≠ AST** — no type information, no overload resolution, no template instantiation. This is by design: the system trades semantic precision for robustness and speed.

3. **Include matching by basename** — ambiguous basenames (3.5%) require suffix matching. Files with identical paths in different roots may mismatch. This is rare in practice.

4. **Trigram tokenizer minimum length** — search terms must be ≥ 3 characters. Single-character or two-character identifiers are not searchable.

5. **No incremental index updates** — `backfill_structural_index` rebuilds all bracket/include data. Individual file updates via `rebuild_structural_index` support incremental changes.

6. **find_callers is text-based** — finds symbol occurrences by name, not by actual call graph analysis. Overloaded functions and template instantiations may produce false positives or false negatives.
