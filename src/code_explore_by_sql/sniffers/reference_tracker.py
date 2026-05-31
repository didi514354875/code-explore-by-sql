"""Reference tracker — builds symbol_references from scanned blocks.

After block sniffing identifies named symbols (classes, functions, enums, etc.),
this module scans file contents for literal identifier references to those symbols,
building MAY_USE edges that form a pre-computed caller/callee graph.

Design principles:
- Literal-only: no AST, no overload resolution, no template instantiation
- Block-type-aware: only tracks refs inside function/method/class/enum blocks
- Provider-agnostic: uses skip_line_re from provider to ignore macro lines
- Context-aware: generic names only tracked as structural references (calls, member access)
"""
from __future__ import annotations

import re
from bisect import bisect_right
from dataclasses import dataclass, field
from typing import Any

TargetSymbol = tuple[str, int, int] | dict[str, Any]

# Block types that produce meaningful references.
# namespace/file-level code is NOT tracked — include_edges covers file-level deps.
_TRACKABLE_BLOCK_TYPES: frozenset[str] = frozenset({
    'function', 'method', 'class', 'enum', 'macro_def',
})


@dataclass(frozen=True)
class ReferenceTrackerConfig:
    """Configuration for reference tracking."""
    # Minimum uniqueness: only track symbols defined in <= this many files.
    max_definition_count: int = 20
    # Minimum symbol name length to track (avoid tracking 2-char identifiers)
    min_name_length: int = 3
    # C/C++ keywords to skip (these are not user-defined symbols)
    skip_keywords: frozenset[str] = field(
        default_factory=lambda: frozenset({
            'auto', 'break', 'case', 'char', 'const', 'continue', 'default',
            'do', 'double', 'else', 'enum', 'extern', 'float', 'for',
            'goto', 'if', 'inline', 'int', 'long', 'namespace', 'register',
            'return', 'short', 'signed', 'sizeof', 'static', 'struct',
            'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile',
            'while', 'class', 'private', 'protected', 'public', 'template',
            'this', 'try', 'catch', 'throw', 'new', 'delete', 'true',
            'false', 'nullptr', 'bool', 'virtual', 'override', 'final',
            'friend', 'using', 'typename', 'explicit', 'export', 'mutable',
            'int32', 'int64', 'uint32', 'uint64',
            'string', 'std', 'NULL', 'TRUE', 'FALSE',
        })
    )


# Word boundary regex: matches C/C++ identifiers
_IDENTIFIER_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\b')

# Member variable type pattern: TypeLetterCamelCase followed by pointer/ref and a name
_MEMBER_TYPE_RE = re.compile(
    r"\b([A-Z][A-Za-z0-9_]+)\s*[\*&]?\s+\w+\s*[;=]"
)

# Maximum references per symbol per file — prevents template-heavy headers
# from bloating the table.  FTS5 handles dense occurrences just fine.
_MAX_REFS_PER_SYMBOL_PER_FILE = 50


def _is_structural_reference(line: str, start: int, end: int) -> bool:
    """Check whether the identifier at line[start:end] appears in a structural context.

    Structural = the identifier is being called, accessed, used as a template arg,
    qualified with ::, or used as a type (followed by * or &).

    Returns False for bare standalone identifiers that happen to match a symbol name.
    """
    llen = len(line)
    # After: ( < :: . ->
    if end < llen:
        ch = line[end]
        if ch in '({<':
            return True
        if ch == ':' and end + 1 < llen and line[end + 1] == ':':
            return True
        if ch == '.':
            return True
        if ch == '>' and end + 1 < llen and line[end - 1:end + 1] == '->':
            return True
    # Before: -> . :: new
    if start > 0:
        ch = line[start - 1]
        if ch == '.':
            return True
        if ch == '>' and start >= 2 and line[start - 2:start] == '->':
            return True
        if ch == ':' and start >= 2 and line[start - 2:start] == '::':
            return True
        # "new SymbolName" pattern
        if start >= 4 and line[start - 4:start].endswith('new '):
            return True
    # Type context: followed by * or & or a space then identifier (type decl)
    # Check if followed by pointer/ref/identifier pattern
    rest = line[end:].lstrip() if end < llen else ''
    if rest and rest[0] in '*&':
        return True
    return False


def _build_line_to_block_type(
    bracket_data: list[dict[str, Any]],
) -> dict[int, str]:
    """Build a mapping from line number (1-based) to the block_type of the
    deepest enclosing bracket block, for lines that fall inside a trackable block.

    Only includes lines inside blocks with types in _TRACKABLE_BLOCK_TYPES.
    """
    if not bracket_data:
        return {}

    # Sort by open_line for processing
    sorted_blocks = sorted(bracket_data, key=lambda b: b["open_line"])

    # Build interval tree: for each line, find the deepest enclosing block
    # We use a simple approach: build (open, close, depth, block_type) list
    intervals = [
        (b["open_line"], b["close_line"], b.get("depth", 0), b.get("block_type", "unknown"))
        for b in sorted_blocks
    ]

    # For each line in each interval, record the deepest block_type
    line_map: dict[int, str] = {}
    for open_l, close_l, depth, bt in intervals:
        if bt not in _TRACKABLE_BLOCK_TYPES:
            continue
        for ln in range(open_l, close_l + 1):
            existing = line_map.get(ln)
            if existing is None:
                line_map[ln] = bt
            # Keep the deeper block's type (inner block wins)

    return line_map


def _extract_type_refs_from_class_body(
    lines: list[str],
    open_line: int,
    close_line: int,
    check_set: set[str],
    skip_line_re: re.Pattern | None = None,
) -> list[str]:
    """Extract type names used in member variable declarations within a class body.

    Returns list of type names that are in check_set.
    """
    types: list[str] = []
    for line_idx in range(open_line, close_line):
        if line_idx >= len(lines):
            break
        line = lines[line_idx].strip()
        if not line:
            continue
        if skip_line_re and skip_line_re.match(line):
            continue
        if line.startswith("//") or line.startswith("/*") or line.startswith("#"):
            continue
        if line in ("public:", "private:", "protected:"):
            continue
        for m in _MEMBER_TYPE_RE.finditer(line):
            tname = m.group(1)
            if tname in check_set:
                types.append(tname)
    return types


def track_references_for_file(
    lines: list[str],
    file_id: int,
    target_symbols: dict[str, list[TargetSymbol]],
    skip_line_re: re.Pattern | None = None,
    check_set: set[str] | None = None,
    skip_names: frozenset[str] | None = None,
    bracket_data: list[dict[str, Any]] | None = None,
) -> list[tuple]:
    """Track references within a single file to known symbols.

    Per-line regex scan with set lookup.  Returns tuples directly — no dataclass allocation.

    Block-type-aware:
    - Only tracks refs inside function/method/class/enum/macro_def blocks
    - File-level and namespace-level code is skipped (include_edges covers file deps)
    - class blocks produce type-dependency refs (member variable types only)
    - function/method blocks produce call-graph refs (all identifier refs with context filtering)

    Args:
        lines: Pre-split lines of the file.
        file_id: The source_files.id of this file.
        target_symbols: Pre-built dict of name -> [symbol records, ...].
        skip_line_re: Regex to skip lines (e.g., UE macro lines).
        check_set: Pre-built set of target symbol names.
        skip_names: Provider-provided noise words.  For these, only structural
                    references (calls, member access, template usage) are kept.
        bracket_data: Bracket block metadata for this file (list of dicts with
                      open_line, close_line, depth, block_type keys).
                      Used for block-type-aware filtering.
    """
    if not target_symbols:
        return []

    if check_set is None:
        check_set = set(target_symbols)

    if skip_names is None:
        skip_names = frozenset()

    # Build line -> block_type mapping
    line_bt: dict[int, str] = {}
    # Track which lines belong to class blocks (for type-only ref extraction)
    class_blocks: list[tuple[int, int]] = []  # (open_line, close_line)

    if bracket_data:
        for b in bracket_data:
            bt = b.get("block_type", "unknown")
            if bt not in _TRACKABLE_BLOCK_TYPES:
                continue
            ol = b["open_line"]
            cl = b["close_line"]
            for ln in range(ol, cl + 1):
                line_bt[ln] = bt
            if bt == "class":
                class_blocks.append((ol, cl))

    refs: list[tuple] = []

    # Phase 1: Extract type-dependency refs from class blocks
    for ol, cl in class_blocks:
        type_names = _extract_type_refs_from_class_body(
            lines, ol, cl, check_set, skip_line_re
        )
        # Find the class block_id for ref_block_id (set later in enrich)
        for tname in type_names:
            for sym in target_symbols.get(tname, []):
                if isinstance(sym, tuple):
                    sym_type, sym_file_id, sym_open_line = sym
                else:
                    sym_type = sym["type"]
                    sym_file_id = sym["file_id"]
                    sym_open_line = sym["open_line"]
                refs.append(
                    (tname, sym_type, sym_file_id, file_id, None, ol)
                )

    # Phase 2: Identifier-based refs for function/method/enum/macro_def blocks
    # Build density counter per symbol per file
    sym_density: dict[str, int] = {}
    in_define = False

    for line_idx, line in enumerate(lines, start=1):
        # --- #define state machine ---
        stripped = line.strip()
        if stripped.startswith('#') and 'define' in stripped:
            in_define = True
            # Don't scan the #define line itself for refs (macro definition, not usage)
            continue
        if in_define:
            if stripped.endswith('\\'):
                continue  # still inside multi-line macro
            in_define = False  # last line of multi-line macro (no trailing \)
            continue

        # --- Skip lines outside trackable blocks ---
        bt = line_bt.get(line_idx)
        if bt is None:
            continue  # file-level or namespace-level — skip
        if bt == "class":
            continue  # class bodies handled by Phase 1 (type deps only)

        # --- Skip UE macro lines ---
        if skip_line_re is not None and skip_line_re.search(line):
            continue

        # --- Scan identifiers ---
        for m in _IDENTIFIER_RE.finditer(line):
            w = m.group(1)
            if w not in check_set:
                continue

            # Density check
            cnt = sym_density.get(w, 0)
            if cnt >= _MAX_REFS_PER_SYMBOL_PER_FILE:
                continue

            # Context check for noise words
            if w in skip_names:
                if not _is_structural_reference(line, m.start(), m.end()):
                    continue

            for sym in target_symbols[w]:
                if isinstance(sym, tuple):
                    sym_type, sym_file_id, sym_open_line = sym
                else:
                    sym_type = sym["type"]
                    sym_file_id = sym["file_id"]
                    sym_open_line = sym["open_line"]
                # Skip self-definition line
                if file_id == sym_file_id and line_idx == sym_open_line:
                    continue
                refs.append(
                    (w, sym_type, sym_file_id, file_id, None, line_idx)
                )
            sym_density[w] = cnt + 1

    return refs


# Type alias for pre-extracted bracket column arrays
BracketArrays = tuple[list[int], list[int], list[int], list[int]]


def prepare_bracket_arrays(
    bracket_data: list[dict[str, Any]],
) -> BracketArrays:
    """Pre-extract column arrays from bracket_data dicts for reuse across calls."""
    return (
        [b["open_line"] for b in bracket_data],
        [b["close_line"] for b in bracket_data],
        [b["id"] for b in bracket_data],
        [b.get("depth", 0) for b in bracket_data],
    )


def enrich_ref_block_ids(
    refs: list[tuple],
    bracket_arrays: BracketArrays,
) -> list[tuple]:
    """Set ref_block_id (index 4) in reference tuples using bisect-based block lookup.

    bracket_arrays: pre-extracted (open_lines, close_lines, block_ids, depths).
    Returns new list of tuples with ref_block_id filled in.
    """
    if not bracket_arrays[0] or not refs:
        return refs

    open_lines, close_lines, block_ids, depths = bracket_arrays

    enriched: list[tuple] = []
    for ref in refs:
        ref_line = ref[5]
        idx = bisect_right(open_lines, ref_line)
        block_id = None
        best_depth = -1
        j = idx - 1
        while j >= 0:
            if open_lines[j] <= ref_line <= close_lines[j]:
                d = depths[j]
                if d > best_depth:
                    block_id = block_ids[j]
                    best_depth = d
            elif close_lines[j] < ref_line and best_depth >= 0:
                # We already found an enclosing block at some depth d.
                # Any block ending before ref_line with depth <= best_depth
                # is a sibling or uncle — can't improve. But a block with
                # depth < best_depth that ends before ref_line means we've
                # passed the region of interest.
                if depths[j] < best_depth:
                    break
            j -= 1
        enriched.append((ref[0], ref[1], ref[2], ref[3], block_id, ref[5]))
    return enriched
