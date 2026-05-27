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

1. **`search_unreal_source(query?, raw_query?, module?, limit?)`** — Search with automatic history acceleration.
2. **`get_file_content(file_path, start_line?, end_line?, anchor?)`** — Read file content (auto-feedback).
3. **`log_unreal_query(query_text, was_useful?, refinement?)`** — Explicit feedback (optional).

## Retrieval procedure

1. **Search** — Call `search_unreal_source` with keywords.
   - Simple: `search_unreal_source(query="GetGBuffer")`
   - Advanced: `search_unreal_source(raw_query='"GetGBuffer" AND "Emissive"')`
   - Results include `source`: `"history_refined"` or `"fts"`.

2. **Read results** — Call `get_file_content` for promising files. Feedback is automatic.

3. **Correct if needed** — Call `log_unreal_query` only if automatic feedback was wrong.

## FTS5 raw_query syntax

| Operator | Example |
|----------|---------|
| AND | `'"A" AND "B"'` |
| OR | `'"A" OR "B"'` |
| NOT | `'"A" NOT "B"'` |
| Grouping | `'("A" OR "B") AND "C"'` |
| Column filter | `'file_path : "BasePass"'` |

Columns: `file_path`, `module_name`, `raw_content`. All terms must be 3+ characters.

## Output expectations

- Candidate file paths and module names
- Code snippets from FTS5
- Line ranges for further reading
