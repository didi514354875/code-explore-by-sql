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

## Retrieval procedure

1. **Check for cached templates**
   - Call `get_query_templates` with the user's intent.
   - Reuse a matching template if one fits.

2. **Search with snippet extraction**
   - Simple search: `search_unreal_source(query="GetGBuffer")`
   - Advanced search with boolean operators: `search_unreal_source(raw_query='"GetGBuffer" AND "Emissive"')`
   - Column-scoped search: `search_unreal_source(raw_query='file_path : "BasePass"')`
   - FTS5 returns filename + code snippet (not whole files).
   - Trigram tokenizer handles code symbols like `GetGBuffer`, `Material.Roughness`.

3. **Read specific lines if needed**
   - Call `get_file_content` with `start_line` and `end_line` only when snippet context is insufficient.

4. **Optionally save template**
   - If the search was useful and likely to recur, suggest saving a template.
   - Ask the user before calling `save_query_template`.

## FTS5 raw_query syntax

| Operator | Example |
|----------|---------|
| AND | `'"A" AND "B"'` |
| OR | `'"A" OR "B"'` |
| NOT | `'"A" NOT "B"'` |
| Grouping | `'("A" OR "B") AND "C"'` |
| Column filter | `'file_path : "BasePass"'` |

Columns: `file_path`, `module_name`, `raw_content`. All terms must be 3+ characters. NEAR and prefix (`*`) do not work with trigram tokenizer.

## Output expectations

- Candidate file paths and module names
- Code snippets from FTS5
- Line ranges for further reading
- Note when DB indexing is needed
