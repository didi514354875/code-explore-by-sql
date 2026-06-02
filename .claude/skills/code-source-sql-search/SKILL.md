---
name: code-source-sql-search
description: "Use when: source code lookup with code-source-sql MCP tools, qualified-symbol lookup, Search_FTS grep-style discovery, Read_Symbol navigation, Read_File_Range location-based reading, macro/delegate/routing inspection, or directory/module lookup."
argument-hint: "Describe the symbol, qualified name, macro, binding, subsystem, or behavior to locate."
user-invocable: true
disable-model-invocation: false
---

# Code Source SQL Search

Use the **`code-source-sql` MCP tools** for source code lookup. This skill follows the semantic retrieval design in `src/code-source-sql/plan.md`: keep the tool surface minimal, retrieve only deterministic anchors, and let the agent reason over qualified names and bounded context.

## Tool surface

### `Read_Symbol(qualified_name, view="full", expand_item=None)`

Precise symbol lookup by qualified name. Primary tool when a qualified name is known or can be inferred.

Semantics:
- Looks up `qualified_name` in `Symbol_Index`.
- Returns bounded source code with `[System Hint]` header (edges, metadata, action guide).
- May list alternative definitions when multiple matches exist.

Use for:
- `ClassName::MethodName` implementations.
- Class, enum, delegate, macro, or method definitions.
- Framework routing targets (e.g., generated `_Implementation` variants).
- Type-dependency guided follow-up lookups.

Rules:
- Prefer qualified names such as `Namespace::Class::Method`, `ClassName::MethodName`, `EnumName::Value`.
- If only a short name is known, use `Search_FTS` first to locate the owner, then call `Read_Symbol` with the qualified name.
- Read the `[System Hint]` before deciding the next lookup.
- Follow explicit static relations from the hint: inheritance, type dependencies, static calls, routing metadata.

### `Search_FTS(keyword, path_filter="", expand_item=None)`

Grep-style full-text search. The **anchor** tool — discovers file, line, owner, and module when no qualified name is available.

Semantics:
- Searches indexed file content with FTS5.
- Returns matching lines with small context.
- `path_filter` narrows results by module/path-like ownership.

Use for:
- Event/callback glue: delegate bindings, callback registrations, event dispatch.
- Framework macro discovery: class/function declarations, code-gen markers.
- Locating the owner of an unqualified function name.
- Finding cross-file glue that is not a precise symbol definition.

Rules:
- Search concrete code tokens, not natural-language phrases.
- Use `path_filter` when results are broad.
- Do not blindly search common method names; first infer the receiver type from nearby context.

### `Read_File_Range(file_path, start_line, end_line, view="full", expand_item=None)`

Read source code by file path and line range, with `[System Hint]` metadata. The **fallback reader** when `Read_Symbol` cannot resolve the correct definition.

Semantics:
- Reads raw source from `file_content` at the given line range.
- Queries `symbol_index` for all symbols intersecting that range.
- Collects edges and metadata for those symbols.
- Returns code with the same `[System Hint]` format as `Read_Symbol`.

Use for:
- `Read_Symbol` returned the wrong definition (e.g., .cpp implementation instead of .h declaration).
- Need to read a specific code region that `Search_FTS` located but `Read_Symbol` cannot target.
- Browsing part of a large class or struct without reading the whole symbol.
- Reading code outside any symbol boundary (e.g., #include blocks, forward declarations).

Rules:
- Use `file_path` as returned by `Search_FTS` results (the `file_path` field).
- Line numbers are 1-based and inclusive on both ends.
- Prefer `Read_Symbol` when a qualified name is known — `Read_File_Range` is the fallback, not the default.
- Use `view="signature"` for large ranges (>100 lines) to avoid token explosion.

### `get_directory_structure()`

Directory/module summary for choosing `path_filter` values.

**MANDATORY — must call before any `Search_FTS` with `path_filter`.**

`path_filter` matches against the actual `module_name` values stored in the database (derived from directory structure at index time). Guessing a module name from framework knowledge will silently drop all results. The only safe sources are:

1. A value returned by `get_directory_structure()` (call it directly, or read `ref/directory-structure.md`).
2. A `module_name` field from a previous tool result (e.g., a `Search_FTS` hit, a `Read_Symbol` entry).

Rules:
- **Before first `Search_FTS` with `path_filter`**: call `get_directory_structure()` once, or read `ref/directory-structure.md` if it exists and is current.
- **Never guess `path_filter` values** from framework knowledge (e.g., "Engine", "Renderer"). They often differ from the actual indexed module names.
- If `path_filter` is not needed (narrow keyword, few expected hits), omit it — this is always safe.
- After calling `get_directory_structure()`, update `ref/directory-structure.md` if it is missing or stale.

Expected `ref/directory-structure.md` format:

```markdown
# Directory Structure
total_files: N
## Valid modules (top 30)
- ModuleName (count)
## False positive modules
- Private
- Public
```

## View parameter strategy

Both `Read_Symbol` and `Read_File_Range` accept a `view` parameter to control output granularity:

| view | Returns | Token cost | When to use |
|------|---------|------------|-------------|
| `"full"` (default) | Complete source code | Normal | Default for small/medium symbols |
| `"signature"` | Only member declarations (function signatures, variables, enums, access specifiers) | ~10-20% | Browsing large classes (>100 lines) |
| `"meta"` | Only `[System Hint]` with edges and metadata, no code | ~2-5% | Quick check on inheritance, dependencies, routing |

Strategy:
1. First encounter with a large symbol → `view="signature"` to scan the public API.
2. Identify target methods → `view="full"` on specific method via `Read_Symbol`.
3. Need only inheritance/dependency info → `view="meta"` before deciding what to read.

## Pipeline — anchor, read, fallback

Three tools, one pipeline. Run per Abstraction Frame layer; move to the next layer when the current layer has enough confirmed anchors.

```
Search_FTS     = Anchor  → "where"  (returns file, line, owner, module)
Read_Symbol    = Read    → "what"   (needs qualified name)
Read_File_Range= Fallback→ "what"   (needs file + line, used when Read_Symbol misses)
```

```
                         Have qualified name?
                              │
                         ┌────┴────┐
                         Yes       No
                         │         │
                         ▼         ▼
                   Read_Symbol   Search_FTS  ← anchor once
                         │         │
                         │    Got qualified name?
                         │         │
                         │    ┌────┴────┐
                         │    Yes       No
                         │    │         │
                         │    ▼         ▼
                         │  Read_Symbol Read_File_Range ← read directly with file+line
                         │    │              │
                         └────┴──────┬───────┘
                                    │
                               Hit & correct?
                                    │
                               ┌────┴────┐
                               Yes       No
                               │         │
                               ▼         ▼
                              Done    Read_File_Range ← fallback with known file+line
```

**Two iron rules:**

1. **Anchor only once.** After `Search_FTS` returns file+line, do not `Search_FTS` again for the same target.
2. **Read_Symbol miss → Read_File_Range directly.** Never re-anchor when you already have file+line.

### Phase 1 — LOCATE (anchor)

Choose one entry:

1. **Known qualified name** → `Read_Symbol("ClassName::MethodName")` directly. Skip anchoring.
2. **Known short name only** → `Search_FTS("ShortName")`, extract owner from results, then `Read_Symbol("Owner::ShortName")`.
3. **Glue code / event binding** → `Search_FTS("binding_macro")` or `Search_FTS("callback_name")`. Narrow with `path_filter` once module ownership is observed.
4. **Unknown entry** → `Search_FTS("ConcreteToken")`. Use concrete code tokens, not natural-language phrases.

### Phase 2 — READ

Use `Read_Symbol` for the best qualified anchor found in Phase 1.

**Miss handling (critical):**

When `Read_Symbol` returns the wrong definition (e.g., .cpp instead of .h, or an unrelated overload):
1. Try a more specific qualified name first (e.g., `Read_Symbol("ClassName")` → try `Read_Symbol("ClassName::MethodName")`). Costs 1 call, may save a fallback.
2. If still wrong, call `Read_File_Range(file_path, start_line, end_line)` with the anchored position.
3. **Do NOT re-anchor.** The position is already known.

For large symbols (>100 lines):
- `view="signature"` first to scan the public API.
- `view="full"` on specific methods via `Read_Symbol`.

While reading:
- Treat `[System Hint]` as authoritative only for deterministic relations.
- Follow routing targets when listed or implied by metadata (e.g., `_Implementation` / `_Validate` suffixes).
- Track type dependencies as candidate owners for later qualified-name lookups.
- Do not invent dynamic call edges from untyped pointer calls.

### Phase 3 — TRACE

Follow deterministic and context-supported relations from `[System Hint]`:

- Static call → `Read_Symbol(target_qualified_name)`.
- Routing metadata → `Read_Symbol("Function_Suffix")` or listed target.
- Type dependency + pointer call → infer `TypeName::MethodName`, then `Read_Symbol`.
- Event/callback binding → `Search_FTS("BoundFunctionName")`, then `Read_Symbol` if owner is identified.

### Phase 4 — CLOSE

Answer with confirmed file/symbol findings, inferred next steps, and unresolved gaps. Mention the exact queries used if the target was not found.

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
| Qualified names | `ClassName::MethodName` |
| Owning types | parent class, component type |
| Routing variants | `_Implementation`, `_Validate` |
| Framework metadata | macro specifiers, routing annotations |
| Glue terms | delegate names, callback names, binding macros |
| Module/path | from `Search_FTS` or `get_directory_structure` |

**Usage:**

- Pass as `expand_item` to any tool call to rank ambiguous results.
- Refresh after every read: add confirmed dependencies, drop unresolved guesses.
- Use to construct the next precise `Read_Symbol` qualified name or choose narrower `Search_FTS` keywords.

**Anti-patterns:**

- Bad: `Search_FTS("Update", expand_item=["everything related"])` without a receiver type.
- Bad: Using `expand_item` as the actual query instead of `qualified_name` / `keyword`.

## Agent reasoning rules

1. The first reasoning unit is the qualified name: `ClassName::MethodName`.
2. `Read_Symbol` is the core read tool. `Search_FTS` is the anchor. `Read_File_Range` is the fallback.
3. **Anchor only once per target.** After `Search_FTS` returns file+line, do not re-anchor.
4. **Miss → fallback, not re-anchor.** `Read_Symbol` returns wrong definition → `Read_File_Range` with known file+line.
5. When seeing `Obj->Update()`, never search `Update` blindly. Infer the receiver type from local variables or `[System Hint]` type dependencies, then use the qualified name.
6. Framework macro metadata is routing information. Follow routing suffixes when listed or implied.
7. Avoid Cartesian explosion: only follow deterministic static relations or context-supported qualified names.

## Failure handling

| Failure | Response |
|---------|----------|
| `Read_Symbol` not found | `Search_FTS` with the shortest distinctive symbol to discover owner |
| `Read_Symbol` returned wrong definition | **Read_File_Range** with file+line from anchor. Do NOT re-`Search_FTS`. |
| `Read_Symbol` miss, no anchor yet | Try more specific qualified name. If still miss, `Search_FTS` to anchor. |
| Short name has too many matches | Add `path_filter` from directory/module ownership |
| FTS query is too broad | Replace with specific macro/function/delegate name or module-specific path filter |
| Pointer call target unknown | Read current symbol, infer receiver type from code/hint, then `Read_Symbol("Type::Method")` |
| Routing target body is thin | Follow routing suffixes (`_Implementation`, `_Validate`, etc.) |
| Callback binding found but target unknown | Search bound function name, then read qualified owner method |
| Symbol too large (>100 lines) | Use `view="signature"` first, then target specific methods |
| Need code outside symbol boundaries | Use `Read_File_Range` |
| More than 5 searches without new signal | Stop and report knowns/unknowns plus next likely query |

## Budget limits

| Resource | Cap |
|----------|-----|
| Abstraction Frame layers | 6 max |
| `Read_Symbol` | ≤8 calls |
| `Search_FTS` | ≤6 calls |
| `Read_File_Range` | ≤4 calls |
| `get_directory_structure` | ≤1 call per session; mandatory before first `Search_FTS` with `path_filter` |

## Output requirements

When answering after lookup:
- Cite file paths and symbols with backticks when returned by tools.
- Separate confirmed facts from inferred next steps.
- Mention module/path ownership when observed.
- If not found, state the exact queries attempted and the next recommended query.
