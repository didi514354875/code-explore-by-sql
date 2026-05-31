# Semantic Block Indexing Design Philosophy

## Core Principle: Language Semantics Over Brace Depth

**"The system builds road signs, the Agent navigates."**

This codebase implements a minimalist topology index designed for LLM agents. The fundamental insight is that **classification should follow language semantics, not brace nesting depth**.

---

## The Problem with Depth-Based Classification

Traditional approach (WRONG):
```
if block.depth == 1:
    classify(block)
else:
    block.type = "unknown"
```

Result: 2.49M blocks, 85% marked "unknown" — pure noise.

**Why depth fails:**
- A method at depth=2 inside a class is semantically meaningful
- A lambda at depth=3 inside a method is noise
- Depth tells you nesting level, not semantic role

---

## The Semantic Solution

New approach (CORRECT):
```
if block.type == 'class':
    explore_methods_inside(block)  # depth=2 methods
elif block.type == 'namespace':
    explore_declarations_inside(block)  # depth=2 classes
```

Result: ~300K-400K blocks, 0% unknown — all meaningful.

**Why semantics work:**
- Language grammar defines containment rules
- A `class` block semantically contains methods and member types
- A `namespace` block semantically contains classes, enums, functions
- We follow the language, not the braces

---

## Architecture: Two-Layer Scanner

### Layer 1: Generic C/C++

**Bracket-based blocks:**
- `namespace` → contains: class, struct, enum, function, macro_def
- `class`/`struct` → contains: method, member_type, nested_class
- `enum` → contains: enumerator values
- `function` → terminal (no further containment)

**Non-bracket blocks:**
- `#define` macros (found by pattern, not braces)
- `typedef` declarations
- Forward declarations

### Layer 2: Project-Specific (Unreal Engine)

**UE decoration macros:**
- `UCLASS(...)`, `USTRUCT(...)`, `UENUM(...)` — store parameters
- `UFUNCTION(...)`, `UPROPERTY(...)` — attach to following declaration

**UE declaration macros:**
- `DECLARE_DELEGATE(...)`, `DECLARE_DYNAMIC_MULTICAST_DELEGATE_*(...)`
- Symbol-defining, no braces, extracted as `ExtraBlock`

---

## Key Design Decisions

### 1. Block = Symbol (Unified Concept)

**Old:** Symbols are strings, blocks are separate structures.
**New:** `symbol_name_index` table where each row IS a symbol pointing to its defining block.

```sql
CREATE TABLE symbol_name_index (
    name TEXT NOT NULL,
    source_type TEXT NOT NULL,    -- 'bracket' or 'extra'
    source_id INTEGER NOT NULL,   -- bracket_index.id or extra_blocks.id
    qualified_name TEXT,          -- "AMyCharacter::BeginPlay"
    member_types TEXT,            -- JSON array for class/struct
    PRIMARY KEY (name, source_type, source_id)
);
```

### 2. Type Dependencies, Not Variable Names

**simplePlan.md principle:** "For member variables, record the TYPE not the variable name."

```cpp
class AMyCharacter {
    UMovementComponent* MoveComp;  // Record: depends on UMovementComponent
    UInventory* Inventory;         // Record: depends on UInventory
};
```

This builds class-to-class dependency edges without noise from variable naming.

### 3. Only Store Classified Blocks

**Old:** Store all 2.49M blocks, mark 85% as "unknown"
**New:** If classifier returns `None`, don't store the block at all

Result: Database shrinks, queries are faster, no noise.

### 4. Fuzzy Search Everywhere

**Problem:** Agent searches "Actor" but code has `AActor`. Trigram FTS5 returns 0 results.

**Solution:** `_fuzzy_resolve_symbol()` with 4-tier fallback:
1. Exact match in `symbol_name_index`
2. UE prefix normalization: `Actor` → try `AActor`, `UActor`, `FActor`, `EActor`, `IActor`, `TActor`
3. Partial match: case-insensitive `LIKE '%Actor%'`
4. Typo correction: `difflib.get_close_matches` with 0.6 cutoff

Returns `did_you_mean` suggestions when no match found.

### 5. Confidence Scoring on Edges

Not all references are equal. Scope proximity scoring:

```python
confidence = 0.5  # baseline
if same_file: confidence += 0.4
elif same_module: confidence += 0.2
elif include_edge_exists: confidence += 0.1

if context == "Super::X": confidence += 0.3  # super call
elif context == "->X": confidence += 0.2     # member call
elif context == "X::Y": confidence += 0.2    # qualified call
```

Agent sees ranked results, not flat lists.

---

## Data Model

### Core Tables

**`bracket_index`** — Brace-delimited blocks (only classified)
- Columns: `file_id`, `open_line`, `close_line`, `depth`, `block_type`, `block_name`, `signature`, `parent_id`, `extra_fields`
- `extra_fields`: JSON with `member_types` array for class/struct blocks

**`extra_blocks`** — Non-brace constructs
- Columns: `file_id`, `name`, `block_type`, `start_line`, `end_line`, `params`, `signature`
- Stores: UE macros, `#define` macros, `DECLARE_*` macros

**`symbol_name_index`** — Unified symbol table
- Maps symbol names to their defining blocks
- `qualified_name` for methods: `ClassName::MethodName`
- `member_types` JSON for class dependencies

**`symbol_references`** — Cross-file references with confidence
- Columns: `symbol_name`, `ref_file_id`, `ref_block_id`, `ref_line`, `confidence`, `context`, `edge_type`
- `edge_type`: `'call'`, `'type_dep'`, `'inherit'`

**`member_types`** — Class-to-class type dependencies
- Extracted from member variable declarations
- Enables "what classes does X depend on?" queries

---

## Semantic Containment Rules

```
namespace MyNS {              // depth=1, type=namespace
    class FRenderer {         // depth=2, type=class (explored because parent is namespace)
        void Render() {       // depth=3, type=method (explored because parent is class)
            if (...) {        // depth=4, NOT STORED (not semantically meaningful)
            }
        }
    };
}
```

**Key insight:** We explore depth=2 blocks when their parent is a container type (`class`, `namespace`), not because they're at depth=2.

---

## Agent-First UX

### Before (Exact Match Only)
```
Agent: search "Actor"
System: 0 results
Agent: [confused, tries "AActor", "UActor", gives up]
```

### After (Fuzzy + Suggestions)
```
Agent: search "Actor"
System: {
  "expanded_from": "Actor",
  "results": [
    {"name": "AActor", "type": "class", "module": "Engine", ...},
    {"name": "UActor", "type": "class", "module": "CoreUObject", ...}
  ]
}
Agent: [immediately finds what it needs]
```

### Structured Returns

**Old:** Raw FTS snippet dumps
```
"snippet": "...virtual void Tick(float DeltaSeconds) override { Super::Tick..."
```

**New:** Structured candidate lists
```json
{
  "candidates": [
    {
      "block_type": "method",
      "qualified_name": "AActor::Tick",
      "file_path": "Engine/.../Actor.h",
      "line_range": "1450-1470",
      "signature": "virtual void Tick(float DeltaSeconds)",
      "module": "Engine",
      "hint": "use get_file_content(anchor='AActor::Tick') to read"
    }
  ]
}
```

Agent can immediately see type, location, signature — no parsing needed.

---

## Performance Characteristics

### Indexing (Backfill)
- **Phase 1:** Bracket scan + semantic sniff (~100s for 84K files)
- **Phase 2:** Parent ID computation (~10s)
- **Phase 3:** Symbol references (~80s)
- **Phase 4:** Symbol name index (~5s)
- **Total:** ~200s for 84K UE files

### Query Performance
- **Exact symbol lookup:** <1ms (indexed)
- **Fuzzy resolution:** <10ms (4-tier fallback)
- **FTS5 search:** <100ms (trigram index)
- **find_callers:** <500ms (bracket skeleton + text scan)
- **find_references:** <50ms (pre-computed)

### Storage
- **Before:** 7.05 GB (2.49M blocks, 85% unknown)
- **After:** ~4-5 GB (300K-400K blocks, 0% unknown, + extra_blocks + symbol_name_index)

---

## Verification Checklist

After backfill, verify:

```sql
-- Block count should drop dramatically
SELECT COUNT(*) FROM bracket_index;  -- ~300K-400K (was 2.49M)

-- No unknown blocks
SELECT COUNT(*) FROM bracket_index WHERE block_type = 'unknown';  -- 0

-- Extra blocks captured
SELECT COUNT(*) FROM extra_blocks;  -- ~50K-100K (UE macros, #define)

-- Symbol table populated
SELECT COUNT(*) FROM symbol_name_index;  -- ~150K-200K

-- Methods visible
SELECT COUNT(*) FROM bracket_index WHERE block_type = 'method';  -- ~100K-200K

-- Type dependencies
SELECT COUNT(*) FROM symbol_references WHERE edge_type = 'type_dep';  -- ~50K-200K

-- Confidence scoring
SELECT AVG(confidence) FROM symbol_references;  -- ~0.6-0.7
```

---

## Design Trade-offs

### What We Gain
- **85% less noise** — only meaningful blocks stored
- **3-5x more symbols** — methods now visible
- **Fuzzy search** — Agent doesn't need exact names
- **Type dependencies** — class-to-class relationships
- **Confidence scoring** — ranked results, not flat lists

### What We Accept
- **No 100% precision** — heuristic classification, not full AST
- **No overload resolution** — literal symbol matching only
- **No template instantiation** — template definitions only
- **False positives in references** — comments/strings may match

**Why this is correct:** LLM agents excel at semantic disambiguation. We provide high-recall candidates (with some noise), the Agent filters to high-precision results. This is the optimal division of labor.

---

## References

- `simplePlan.md` — Original design vision (Chinese)
- `AGENTS.md` — MCP tool API documentation
- `test_bracket_scanner.py` — 53 tests validating scanner behavior
- `test_block_index_data.py` — Data quality metrics and thresholds

---

**Last Updated:** 2026-05-31  
**Implementation Status:** ✅ Complete (All 8 tasks)
