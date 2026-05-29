# AGENTS.md

This repository provides a local MCP server for Unreal Engine source retrieval using **SQLite FTS5** (trigram tokenizer) with a **bracket skeleton structural index**.

## Architecture

One file = one row in `source_files`. FTS5 `snippet()` extracts relevant code fragments via a **two-step deferred query** (rank first, snippet only for top-N, truncated to 300 chars), producing compact ~2,600 token responses for 20 results (95% token reduction vs full snippets).

**Bracket skeleton index**: A 6-state FSM scans C/C++ source tracking brace pairs while ignoring braces in comments, strings, and raw string literals. Each brace pair records depth, open/close line, block type, and block name. This provides structural context without AST parsing — robust against macros and incomplete syntax.

**Include dependency graph**: O(1) basename hash lookup resolves 96.5% of include paths. Supports upstream/downstream traversal with configurable recursion depth.

**History-as-ranking-signal**: Past search feedback adjusts result ranking but never filters out results. This prevents confirmation bias while still accelerating relevant results.

### Token cost quick reference

| Operation | ~Tokens | Note |
|-----------|---------|------|
| `search_unreal_source` (20 results) | ~2,600 | Compact 300-char snippets |
| `get_file_content(anchor=...)` | ~125 | **Always prefer** over full read |
| `get_file_content` (full file) | ~45,000 | Avoid — use anchor or line range |
| `find_callers` (specific symbol) | 127–3,000 | Use `scope` for common symbols |
| `find_include_graph` | 50–2,100 | Cheap — use freely |

## Tools (5)

1. **`search_unreal_source`** — FTS5 search with history ranking, scope filtering, compact snippets.
   - Simple: `query="GetGBuffer"`
   - Advanced: `raw_query='"GetGBuffer" AND "Emissive"'`
   - `scope_filter` must be a **JSON string**: `'{"block_type": "function"}'`
   - `module="Renderer"` — filter by UE module name

2. **`get_file_content`** — Read file content. Prefer **anchor mode** for efficiency.
   - Anchor: `anchor="Render", context_chars=500` (~125 tokens)
   - Line range: `start_line=100, end_line=200`
   - Auto-records feedback from search results

3. **`log_unreal_query`** — Record explicit feedback (optional, only to correct automatic feedback)

4. **`find_include_graph`** — Include dependency graph (upstream/downstream, recursive, depth control)

5. **`find_callers`** — Caller lookup with line-range verification.
   - Returns exact `caller_line` per call site
   - **Always use `scope`** for common symbols like "Render" (500+ callers otherwise)

## Recommended flow

1. `search_unreal_source` → compact snippets (~2,600 tok)
2. `get_file_content(anchor=...)` → deep context (~125 tok each)
3. `find_callers` / `find_include_graph` → structural exploration
4. `log_unreal_query` → only to correct feedback

## FTS5 Query Syntax (for raw_query)

| Operator | Example |
|----------|---------|
| AND | `'"A" AND "B"'` |
| OR | `'"A" OR "B"'` |
| NOT | `'"A" NOT "B"'` |
| Grouping | `'("A" OR "B") AND "C"'` |
| Column filter | `'file_path : "BasePass"'` |

All terms must be 3+ characters. NEAR and prefix (`*`) do NOT work with trigram tokenizer.

## Guidance

- Use the `unreal-source-lookup` skill for detailed tool documentation and search strategy
- Avoid full file reads — anchor mode is 358x cheaper in tokens
- History feedback is automatic — no need to manually log unless correcting
- If the database has not been built yet, guide the user toward indexing first
