---
name: unreal-source-lookup
description: 'Use for Unreal Engine source lookup, symbol tracing, macro/class/function discovery, FTS query planning, and chunk-first code retrieval. Trigger on requests like find Unreal symbol, trace function, search engine source, inspect macro, locate class implementation, reduce token usage.'
argument-hint: 'Describe the Unreal symbol, subsystem, macro, class, or behavior you need to locate.'
user-invocable: true
disable-model-invocation: false
---

# Unreal Source Lookup

Use this skill when the task is about **finding, narrowing, and extracting Unreal Engine source efficiently** with the local MCP server.

## Goals

- Minimize token usage by preferring chunk-level retrieval.
- Reduce latency by avoiding repeated whole-file reads.
- Reuse saved query templates when they match the user intent.
- Keep template persistence semi-automatic.

## When to use

- Find where an Unreal function, class, macro, subsystem, or symbol is implemented
- Trace likely call sites or related engine code
- Search large Unreal source trees without dumping entire files
- Convert repeated user intents into reusable query templates
- Compare whether chunk search is sufficient before reading file ranges

## Retrieval procedure

1. **Check for reusable templates first**
   - If the request sounds repetitive or pattern-based, call `suggest_query_templates` or `get_query_templates`.
   - Reuse a matching template if it clearly fits.

2. **Prefer cached chunk search**
   - Use `search_code_chunks` for direct function/class/macro retrieval.
   - Keep `limit` small and use bounded `body_chars`.

3. **Use combined retrieval when cache coverage may be incomplete**
   - Call `search_then_extract_chunks` to search files and return the best chunks in one step.

4. **Use broad file search only when necessary**
   - Use `search_unreal_source` when you need recall across many files or when chunk search misses.

5. **Use full-file retrieval as fallback**
   - Call `get_file_content` only for focused line ranges or when chunk extraction is not enough.

## Template policy

- You may suggest a new query template when a search pattern is likely to repeat.
- Do not persist a new template automatically.
- Ask the user before calling `save_query_template`.
- If the user gives explicit feedback about a template, record it with `log_unreal_query` and `template_id`.

## Output expectations

Return concise results that help the caller decide the next step:

- candidate file paths
- module names
- symbol names / symbol types
- line ranges
- compact chunk bodies or snippets
- note when fallback to full-file retrieval is necessary

## Escalation rules

- If no relevant chunk is found, broaden to `search_unreal_source`.
- If file-level search is noisy, refine with module filters or a query template.
- If the DB is missing or stale, say that indexing or chunk pre-cache may be required.
