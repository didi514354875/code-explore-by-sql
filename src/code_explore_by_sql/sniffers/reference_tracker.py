"""Reference tracker — builds symbol_references from scanned blocks.

After block sniffing identifies named symbols (classes, functions, enums, etc.),
this module scans file contents for literal identifier references to those symbols,
building MAY_USE edges that form a pre-computed caller/callee graph.

Design principles:
- Literal-only: no AST, no overload resolution, no template instantiation
- Configurable uniqueness threshold: skip tracking very common names (e.g., "Render")
  unless explicitly requested, to keep the table manageable
- Provider-agnostic: uses skip_line_re from provider to ignore macro lines
"""
from __future__ import annotations

import re
from bisect import bisect_right
from dataclasses import dataclass, field
from typing import Any


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
            'int32', 'int64', 'uint32', 'uint64', 'float', 'double',
            'string', 'std', 'NULL', 'TRUE', 'FALSE',
        })
    )


# Word boundary regex: matches C/C++ identifiers
_IDENTIFIER_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\b')


def track_references_for_file(
    lines: list[str],
    file_id: int,
    target_symbols: dict[str, list[dict[str, Any]]],
    skip_line_re: re.Pattern | None = None,
    check_set: set[str] | None = None,
) -> list[tuple]:
    """Track references within a single file to known symbols.

    Per-line regex scan with set lookup. Returns tuples directly — no dataclass allocation.

    Args:
        lines: Pre-split lines of the file.
        file_id: The source_files.id of this file.
        target_symbols: Pre-built dict of name -> [sym_dict, ...].
            Sym dicts must have keys: 'name', 'type', 'file_id', 'open_line'.
        skip_line_re: Regex to skip lines (e.g., UE macro lines).
        check_set: Pre-built set of target symbol names. If None, derived from target_symbols.

    Returns:
        List of tuples: (sym_name, sym_type, sym_file_id, ref_file_id, ref_block_id, ref_line)
        where ref_block_id is always None (enriched later).
    """
    if not target_symbols:
        return []

    if check_set is None:
        check_set = set(target_symbols)

    refs: list[tuple] = []
    for line_idx, line in enumerate(lines, start=1):
        # Skip UE macro lines
        if skip_line_re is not None and skip_line_re.search(line):
            continue

        for m in _IDENTIFIER_RE.finditer(line):
            w = m.group(1)
            if w not in check_set:
                continue
            for sym in target_symbols[w]:
                # Skip self-definition line
                if file_id == sym["file_id"] and line_idx == sym["open_line"]:
                    continue
                refs.append(
                    (w, sym["type"], sym["file_id"], file_id, None, line_idx)
                )

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
            if close_lines[j] < ref_line:
                break
            if open_lines[j] <= ref_line <= close_lines[j]:
                d = depths[j]
                if d > best_depth:
                    block_id = block_ids[j]
                    best_depth = d
            j -= 1
        enriched.append((ref[0], ref[1], ref[2], ref[3], block_id, ref[5]))
    return enriched
