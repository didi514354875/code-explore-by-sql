---
name: unreal-source-lookup
description: 'Use for Unreal Engine source lookup and symbol search. Trigger on requests like find Unreal symbol, trace function, search engine source, inspect macro, locate class implementation.'
argument-hint: 'Describe the Unreal symbol, subsystem, macro, class, or behavior you need to locate.'
user-invocable: true
disable-model-invocation: false
---

# Unreal Source Lookup

Use this skill when the task is about **finding Unreal Engine source efficiently** with the local MCP server.

## Retrieval procedure

1. **Check for cached templates**
   - Call `get_query_templates` with the user's intent.
   - Reuse a matching template if one fits.

2. **Search with snippet extraction**
   - Call `search_unreal_source` with keywords.
   - FTS5 returns filename + code snippet (not whole files).
   - Trigram tokenizer handles code symbols like `GetGBuffer`, `Material.Roughness`.

3. **Read specific lines if needed**
   - Call `get_file_content` with `start_line` and `end_line` only when snippet context is insufficient.

4. **Optionally save template**
   - If the search was useful and likely to recur, suggest saving a template.
   - Ask the user before calling `save_query_template`.

## Output expectations

- Candidate file paths and module names
- Code snippets from FTS5
- Line ranges for further reading
- Note when DB indexing is needed
