---
name: code-source-sql-search
description: "Use when: source code lookup with the new code-source-sql MCP tools, UE C++ qualified-symbol lookup, Search_FTS grep-style discovery, Read_Symbol navigation, Read_File_Range location-based reading, macro/RPC/delegate inspection, or directory/module lookup."
argument-hint: "Describe the UE symbol, qualified name, macro, delegate binding, subsystem, or behavior to locate."
user-invocable: true
disable-model-invocation: false
---

# Code Source SQL Search

Use the **new `code-source-sql` MCP tools** for UE source lookup. This skill follows the semantic retrieval design in `src/code-source-sql/plan.md`: keep the tool surface minimal, retrieve only deterministic anchors, and let the agent reason over qualified names and bounded context.

## Tool surface

### `Read_Symbol(qualified_name, view="full", expand_item=None)`

Precise symbol lookup by qualified name. Primary navigation tool when a qualified name is known or can be inferred.

Semantics:
- Looks up `qualified_name` in `Symbol_Index`.
- Returns bounded source code with `[System Hint]` header (edges, UE metadata, action guide).
- May list alternative definitions when multiple matches exist.

Use for:
- `ClassName::MethodName` implementations.
- Class, enum, delegate, macro, or method definitions.
- UE RPC / BlueprintNativeEvent routing targets.
- Type-dependency guided follow-up lookups.

Rules:
- Prefer qualified names such as `ACharacter::Jump`, `UWeaponComponent::PrepareWeapon`, `EPhase::Type`.
- If only a short name is known, use `Search_FTS` first to locate the owning class/module, then call `Read_Symbol` with the qualified name.
- Read the `[System Hint]` before deciding the next lookup.
- Follow explicit static relations from the hint: inheritance, type dependencies, static calls, and RPC routing.

### `Search_FTS(keyword, path_filter="", expand_item=None)`

Grep-style full-text search. Use this for discovery and glue code when no qualified symbol is available.

Semantics:
- Searches indexed file content with FTS5.
- Returns matching lines with small context.
- `path_filter` narrows results by module/path-like ownership.

Use for:
- Delegate/event glue: `AddDynamic`, `AddUObject`, `Bind`, `Broadcast`.
- UE macro discovery: `UCLASS`, `UFUNCTION`, `DECLARE_`, RPC specifiers.
- Locating the owner of an unqualified function name.
- Finding cross-file glue that is not a precise symbol definition.

Rules:
- Search concrete code tokens, not natural-language phrases.
- Use `path_filter` when results are broad.
- Combine glue terms with specific event/function names through successive searches.
- Do not blindly search common untyped calls like `Update`; first infer the receiver type from nearby context.

### `Read_File_Range(file_path, start_line, end_line, view="full", expand_item=None)`

Read source code by file path and line range, with `[System Hint]` metadata from symbol_index and edges. Use this as the **fallback reader** when `Read_Symbol` cannot resolve the correct definition.

Semantics:
- Reads raw source from `file_content` at the given line range.
- Queries `symbol_index` for all symbols intersecting that range.
- Collects edges and UE metadata for those symbols.
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

Rules:
- If `ref/directory-structure.md` exists, read it first.
- If missing or stale, call `get_directory_structure()` and update `ref/directory-structure.md` with a slim summary.
- Use discovered module/path ownership as `path_filter` in `Search_FTS`.

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
| `"meta"` | Only `[System Hint]` with edges and UE metadata, no code | ~2-5% | Quick check on inheritance, dependencies, RPC routing |

Strategy:
1. First encounter with a large symbol → `view="signature"` to scan the public API.
2. Identify target methods → `view="full"` on specific method via `Read_Symbol`.
3. Need only inheritance/dependency info → `view="meta"` before deciding what to read.

## Tool relationship — anchor, read, fallback

Three tools, two phases, one pipeline:

```
Search_FTS     = Anchor  → "where"  (returns file, line, owner, module)
Read_Symbol    = Read    → "what"   (needs qualified name)
Read_File_Range= Fallback→ "what"   (needs file + line, used when Read_Symbol misses)
```

**The only pipeline:**

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

1. **Anchor only once.** After `Search_FTS` returns file+line, do not `Search_FTS` again for the same target. The position is known.
2. **Read_Symbol miss → Read_File_Range directly.** Never re-anchor when you already have file+line. Go straight to fallback.

## Tool selection by intent

| Intent | Entry | If miss |
|--------|-------|---------|
| Known qualified name | `Read_Symbol` | `Read_File_Range` (from `Search_FTS` anchor first) |
| Unknown name, keyword only | `Search_FTS` → `Read_Symbol` | `Read_File_Range` with file+line from `Search_FTS` |
| Glue code / macros / delegates | `Search_FTS` | — |
| Browse large class API | `Read_Symbol` with `view="signature"` | `Read_File_Range` with `view="signature"` |
| Check inheritance/dependencies only | `Read_Symbol` with `view="meta"` | `Read_File_Range` with `view="meta"` |
| Code outside any symbol | `Read_File_Range` | — |

## Abstraction Frame — mandatory semantic frame

Before any code lookup tool call, state an Abstraction Frame for the user's intent.

The Abstraction Frame describes architectural slices of the target system. It is **not** a search plan. Each layer must represent one system role.

Format:

```text
ABSTRACTION FRAME (for "<user intent>"):
  Layer 1: [Core Abstractions] — public interfaces, base types, symbols, or top-level concepts
  Layer 2: [Entry Points / Coordinator] — central manager, lifecycle, dispatch, or externally called API
  Layer 3: [State / Storage] — persistent data, cached state, registries, ownership, or memory layout
  Layer 4: [Execution Flow] — concrete implementations and deterministic static calls
  Layer 5: [Glue / Integration] — UE macros, delegates, bindings, generated routing, event wiring
  Layer 6: [Boundaries] — modules, include boundaries, platform/RHI/subsystem seams
```

Keep at most 6 layers. For narrow symbol lookups, 2-3 layers are enough.

Example:

```text
ABSTRACTION FRAME (for "追踪 UE RPC 函数 ServerEquipWeapon"):
  Layer 1: [Public Contract] — UFUNCTION 声明与 RPC metadata
  Layer 2: [Routing Target] — _Implementation / _Validate 真实执行入口
  Layer 3: [Type Dependencies] — 参数类型和拥有者组件
  Layer 4: [Runtime Flow] — 函数体内的静态调用和指针调用上下文
  Layer 5: [Glue] — 宏、delegate、binding 或生成式路由
```

## Search pipeline

Run the pipeline per Abstraction Frame layer. Move to the next layer when the current layer has enough confirmed anchors.

### Phase 1 — LOCATE

Choose one:

1. Known qualified symbol:
   - Call `Read_Symbol("ClassName::MethodName")`.
   - Use returned `[System Hint]` to identify routing targets and type dependencies.

2. Known short symbol only:
   - Call `Search_FTS("ShortName", path_filter="optional module")`.
   - Inspect returned file/module context.
   - Convert to a qualified name.
   - Call `Read_Symbol("Owner::ShortName")`.

3. Glue code / event binding:
   - Call `Search_FTS("AddDynamic")`, `Search_FTS("Bind")`, or a specific delegate/function name.
   - Narrow with `path_filter` once module ownership is observed.

4. Unknown subsystem entry:
   - Call `Search_FTS("ConcreteClassOrMacroOrFunction")`.
   - Avoid natural-language queries; use 2-3 concrete code tokens across separate searches if needed.

### Phase 2 — READ

Use `Read_Symbol` for the best qualified anchor found in Phase 1.

**Read_Symbol miss handling (critical):**

When `Read_Symbol` returns the wrong definition (e.g., .cpp instead of .h, or an unrelated overload):
1. You already have file+line from Phase 1 anchor — **use it directly**.
2. Call `Read_File_Range(file_path, start_line, end_line)` with the anchored position.
3. **Do NOT call `Search_FTS` again** for the same target. The anchor is already known.
4. `Read_File_Range` returns the same `[System Hint]` format, so no information is lost.

**Alternative: try a more specific qualified name first.**
If `Read_Symbol("FShaderType")` misses, try `Read_Symbol("FShaderType::FShaderType")` (constructor) before falling back to `Read_File_Range`. This costs 1 call and may save a `Read_File_Range`.

For large symbols (>100 lines of code):
- Use `view="signature"` first to browse the public API.
- Then use `Read_Symbol` with the specific method name and `view="full"` to read the target.

While reading:
- Treat `[System Hint]` as authoritative only for deterministic relations.
- Follow RPC targets such as `_Implementation` / `_Validate` when listed or implied by metadata.
- Track type dependencies as candidate owners for later qualified-name lookups.
- Do not invent dynamic call edges from untyped pointer calls.

### Phase 3 — TRACE

Follow deterministic and context-supported relations:
- Static call relation from `[System Hint]` → `Read_Symbol(target_qn)`.
- RPC routing metadata → `Read_Symbol("Function_Implementation")` or listed target.
- Type dependency + pointer call → infer `TypeName::MethodName`, then `Read_Symbol`.
- Delegate binding → `Search_FTS("BoundFunctionName")` or `Search_FTS("DelegateName")`, then `Read_Symbol` if an owner is identified.

### Phase 4 — ENRICH

Maintain an agent-side set of confirmed qualified names, owning classes, modules, and glue terms. Use this set to choose the next `Read_Symbol` or `Search_FTS` call.

### Phase 5 — CLOSE

Answer with confirmed file/symbol findings, inferred next steps, and unresolved gaps. Mention the exact `Read_Symbol` / `Search_FTS` / `Read_File_Range` queries used if the target was not found.

## Agent reasoning rules from `plan.md`

1. The first reasoning unit is the qualified name: `ClassName::MethodName`.
2. `Read_Symbol` is the core precise navigation tool.
3. `Search_FTS` is the anchor — for discovering owner, file, line, module. Use once per target.
4. `Read_File_Range` is the fallback when `Read_Symbol` cannot target the correct code. Use with file+line from anchor, never re-anchor.
5. **Iron rule: anchor only once.** After `Search_FTS` returns file+line for a target, all subsequent reads use that position. Do not `Search_FTS` the same name again.
6. **Iron rule: miss → fallback, not re-anchor.** When `Read_Symbol` returns wrong definition, go directly to `Read_File_Range` with the known file+line. Re-anchoring wastes calls.
7. When seeing `Obj->Update()` or `Comp.Init()`, never search `Update` blindly.
   - Inspect local variable type.
   - Inspect `[System Hint]` type dependencies.
   - Infer a qualified target such as `UMyComponent::Update` before calling `Read_Symbol`.
8. UE macro metadata is routing information:
   - `Server`, `Client`, `NetMulticast`, `BlueprintNativeEvent` often route to `_Implementation`.
   - Validation variants may route to `_Validate`.
9. Delegates and events are glue:
   - Use `Search_FTS` for `AddDynamic`, `AddUObject`, `Bind`, `Broadcast`, `DECLARE_`, delegate names, and bound function names.
10. Avoid Cartesian explosion:
    - Do not build generic call chains from common method names.
    - Only follow deterministic static relations or context-supported qualified names.

## Signal enrichment

`expand_item` is the new-tool equivalent of Signal enrichment. It is ranking acceleration and result annotation, **not** intent expansion.

Core rule:
- `qualified_name` / `keyword` remains the real query.
- `expand_item` contains confirmed or estimated signals that help ranking when multiple candidates match.
- `expand_item` must never be used as a substitute for the actual query.

### What signal enrichment means now

Maintain a compact working set of confirmed signals:
- Qualified names: `ClassName::MethodName`.
- Owning classes/types: `ACharacter`, `UWeaponComponent`.
- Routing variants: `_Implementation`, `_Validate`.
- UE metadata terms: `UFUNCTION(Server)`, `BlueprintNativeEvent`, `DECLARE_...`.
- Glue terms: delegate names, bound function names, `AddDynamic`, `Bind`.
- Module/path ownership from `Search_FTS` or `get_directory_structure`.

Use these signals to:
- Pass `expand_item` to `Read_Symbol` when partial or fuzzy symbol lookup may return multiple candidates.
- Pass `expand_item` to `Search_FTS` to rank grep results that mention confirmed classes, routes, delegates, or modules.
- Pass `expand_item` to `Read_File_Range` to rank/annotate intersecting symbols.
- Construct the next precise `Read_Symbol` qualified name.
- Choose a narrower `Search_FTS` keyword and `path_filter`.
- Avoid broad, stale, or generic searches.

### Progressive enrichment loop

1. Seed signals from the user's request.
   - Example: request mentions `ServerEquipWeapon` → seed `ServerEquipWeapon`, `ServerEquipWeapon_Implementation`, `ServerEquipWeapon_Validate`.

2. Discover ownership when the qualified name is missing.
   - `Search_FTS("ServerEquipWeapon")`.
   - Extract owner class and module/path from returned context.

3. Convert signals into precise lookups.
   - `Read_Symbol("AMyCharacter::ServerEquipWeapon", expand_item=["ServerEquipWeapon_Implementation", "UWeaponComponent"])`.
   - Then follow `[System Hint]` to `AMyCharacter::ServerEquipWeapon_Implementation`.

4. Refresh signals after every read.
   - Add confirmed type dependencies and static targets.
   - Drop guessed names that did not resolve.
   - Prefer qualified names over short names.

5. Use signals to constrain future FTS.
   - Good: `Search_FTS("AddDynamic", path_filter="ProjectX", expand_item=["OnDeath", "AMyActor"])` after module ownership is known.
   - Good: `Search_FTS("OnDeath", path_filter="ProjectX", expand_item=["HandleDeath"])` after delegate name is confirmed.
   - Bad: repeated `Search_FTS("Update", expand_item=["everything related"])` without a receiver type.

### Signal enrichment examples

RPC progression:

```text
Seed: ServerEquipWeapon
Search_FTS("ServerEquipWeapon", expand_item=["ServerEquipWeapon_Implementation", "ServerEquipWeapon_Validate"]) → confirms AMyCharacter and ProjectX module
Read_Symbol("AMyCharacter::ServerEquipWeapon", expand_item=["ServerEquipWeapon_Implementation", "UWeaponComponent"]) → hint says RPC target _Implementation, type dependency UWeaponComponent
Read_Symbol("AMyCharacter::ServerEquipWeapon_Implementation", expand_item=["UWeaponComponent", "PrepareWeapon"])
If body has WeaponComp->PrepareWeapon(...), infer UWeaponComponent::PrepareWeapon
Read_Symbol("UWeaponComponent::PrepareWeapon", expand_item=["FWeaponData"])
```

Large class progression:

```text
Seed: FShaderType
Search_FTS("class FShaderType") → anchor: Shader.h:1238, range 1238-1566
Read_Symbol("FShaderType") → returns Shader.cpp implementation (wrong def)
  → Do NOT re-Search. Anchor already has file+line.
Read_File_Range("Source/Runtime/RenderCore/Public/Shader.h", 1238, 1566, view="signature") → browses class API
Read_Symbol("FShaderType::GetHashedName") → reads specific method with full code
```

Delegate progression:

```text
Seed: OnDeath, AddDynamic
Search_FTS("AddDynamic", path_filter="ProjectX", expand_item=["OnDeath"]) → finds OnDeath.AddDynamic(this, &AMyActor::HandleDeath)
Read_Symbol("AMyActor::HandleDeath", expand_item=["OnDeath", "Broadcast"])
Search_FTS("OnDeath", path_filter="ProjectX", expand_item=["HandleDeath", "Broadcast"]) → find broadcaster or declaration if needed
```

Subsystem progression:

```text
Seed: VirtualTexture, FVirtualTextureSystem
Search_FTS("FVirtualTextureSystem", expand_item=["VirtualTexture", "PageTable"]) → confirms module/path and exact class owner
Read_Symbol("FVirtualTextureSystem", expand_item=["FVirtualTextureSpace", "FAllocatedVirtualTexture"])
Use hint/type dependencies to collect FVirtualTextureSpace, FAllocatedVirtualTexture
Read_Symbol("FVirtualTextureSpace", expand_item=["PageTable"]) or Search_FTS("PageTable", path_filter="Renderer", expand_item=["FVirtualTextureSpace"])
```

## Failure handling

| Failure | Response |
|---------|----------|
| `Read_Symbol` not found | `Search_FTS` with the shortest distinctive symbol to discover owner |
| `Read_Symbol` returned wrong definition | **Read_File_Range** with file+line from anchor. Do NOT re-`Search_FTS`. |
| `Read_Symbol` miss, no anchor yet | Try `Read_Symbol("ClassName::MethodName")` with more specific qualified name. If still miss, `Search_FTS` to anchor. |
| Short name has too many matches | Add `path_filter` from directory/module ownership |
| FTS query is too broad | Replace with macro/delegate/function name or module-specific path filter |
| Pointer call target unknown | Read current symbol, infer receiver type from code/hint, then `Read_Symbol("Type::Method")` |
| RPC base function found but body is thin | Follow `_Implementation` / `_Validate` |
| Delegate binding found but target unknown | Search bound function name, then read qualified owner method |
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
| `get_directory_structure` | ≤1 call, only if ref is missing/stale |

## Output requirements

When answering after lookup:
- Cite file paths and symbols with backticks when returned by tools.
- Separate confirmed facts from inferred next steps.
- Mention module/path ownership when observed.
- If not found, state the exact `Read_Symbol` / `Search_FTS` / `Read_File_Range` queries attempted and the next recommended query.
