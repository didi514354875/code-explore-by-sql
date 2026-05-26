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

3. **Extract context around a known symbol**
   - Prefer anchor mode over full-file reads: `get_file_content(file_path="...", anchor="void FMyClass::MyMethod")`
   - Anchor mode uses SQL `instr()` + `substr()` to return only a ~500-char window centered on the match — avoids loading a 27KB file for one function.
   - `context_chars` defaults to 500 (~12-15 lines); increase for wider context: `context_chars=1500`.
   - Fall back to `start_line`/`end_line` only when you know exact line numbers (e.g., from prior output).

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

## Query template writing best practices

When crafting or updating `fts_template` for `save_query_template` / `update_query_template`:

1. **Always scope with `file_path` column filter**
   - FTS5 trigram index covers all 84K+ source files; unscoped queries scan the entire corpus.
   - Prefix every domain-specific template with `(file_path : "Keyword") AND` to narrow candidates to a subset.
   - Example: `(file_path : "Nanite") AND "FBuilderModule"` instead of bare `"FBuilderModule"`.

2. **Validate every OR branch before saving**
   - Use `search_unreal_source(raw_query='"SymbolName"')` to confirm each symbol exists in the index.
   - Remove branches that return 0 hits — they add scanning overhead with no recall benefit.
   - Re-run validation after UE version upgrades, as symbols may be renamed or removed.

3. **Avoid short or generic terms in OR branches**
   - Trigram tokenizer matches any 3+ char substring, so short words like `Split` match unrelated symbols (`BSplitter`, `SplitMesh`, etc.).
   - Prefer the most specific symbol available: `"FClusterGroup"` over `"Split"`.
   - If a generic term is unavoidable, rely on the `file_path` scope + AND constraint to keep the result set small.

4. **Structure: scope → anchor → variants**
   ```
   (file_path : "Domain") AND "AnchorSymbol" AND ("Variant1" OR "Variant2")
   ```
   - `file_path` scope first (cheap column filter, reduces candidate set 100×).
   - `AND "AnchorSymbol"` second (high-precision anchor that must appear).
   - `OR` variants last (expand recall within the already-narrowed set).

5. **Update existing templates rather than creating duplicates**
   - Use `update_query_template(template_id=..., fts_template=...)` to refine an existing template.
   - This preserves accumulated `success_rate` and `example_queries` feedback history.

## Output expectations

- Candidate file paths and module names
- Code snippets from FTS5
- Line ranges for further reading
- Note when DB indexing is needed
