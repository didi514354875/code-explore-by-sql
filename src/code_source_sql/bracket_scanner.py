"""Bracket skeleton scanner — lightweight structural indexing for C/C++ source.

FSM tracks brace depth while correctly ignoring braces inside comments,
string literals, character literals, and raw strings.
"""

from __future__ import annotations

from dataclasses import dataclass

# FSM states
_CODE = 0
_LINE_COMMENT = 1
_BLOCK_COMMENT = 2
_STRING = 3
_CHAR_LITERAL = 4
_RAW_STRING = 5

_TRIGGER_CHARS = frozenset('{}"/\'R')


@dataclass(frozen=True)
class BracketBlock:
    open_line: int      # 1-based
    close_line: int     # 1-based
    depth: int
    is_complete: bool


def scan_brackets(content: str) -> list[BracketBlock]:
    """Scan content and return matched brace pairs with depth info."""
    depth = 0
    stack: list[tuple[int, int]] = []  # (open_line, open_depth)
    blocks: list[BracketBlock] = []
    state = _CODE
    raw_delim = ""

    lines = content.split("\n")
    last_line = len(lines)

    for line_idx, line in enumerate(lines, start=1):
        if state == _CODE and not any(c in line for c in _TRIGGER_CHARS):
            continue

        i = 0
        n = len(line)
        while i < n:
            ch = line[i]
            next_ch = line[i + 1] if i + 1 < n else ""

            if state == _CODE:
                if ch == "/" and next_ch == "/":
                    state = _LINE_COMMENT
                    i += 2
                    continue
                if ch == "/" and next_ch == "*":
                    state = _BLOCK_COMMENT
                    i += 2
                    continue
                if ch == "R" and next_ch == '"':
                    delim_end = line.find("(", i + 2)
                    if delim_end != -1:
                        raw_delim = line[i + 2 : delim_end]
                        state = _RAW_STRING
                        i = delim_end + 1
                        continue
                if ch == '"':
                    state = _STRING
                    i += 1
                    continue
                if ch == "'":
                    state = _CHAR_LITERAL
                    i += 1
                    continue

                if ch == "{":
                    depth += 1
                    stack.append((line_idx, depth))
                elif ch == "}":
                    if stack:
                        open_line, open_depth = stack.pop()
                        blocks.append(BracketBlock(
                            open_line=open_line,
                            close_line=line_idx,
                            depth=open_depth,
                            is_complete=True,
                        ))
                    depth = max(0, depth - 1)

                i += 1

            elif state == _LINE_COMMENT:
                break

            elif state == _BLOCK_COMMENT:
                if ch == "*" and next_ch == "/":
                    state = _CODE
                    i += 2
                    continue
                i += 1

            elif state == _STRING:
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    state = _CODE
                i += 1

            elif state == _CHAR_LITERAL:
                if ch == "\\":
                    i += 2
                    continue
                if ch == "'":
                    state = _CODE
                i += 1

            elif state == _RAW_STRING:
                end_marker = ")" + raw_delim + '"'
                pos = line.find(end_marker, i)
                if pos != -1:
                    state = _CODE
                    i = pos + len(end_marker)
                    continue
                break

        if state == _LINE_COMMENT:
            state = _CODE

    for open_line, open_depth in stack:
        blocks.append(BracketBlock(
            open_line=open_line,
            close_line=last_line,
            depth=open_depth,
            is_complete=False,
        ))

    return blocks


def compute_parent_map(blocks: list[BracketBlock]) -> dict[tuple[int, int], tuple[int, int] | None]:
    """Compute parent for each block based on nesting.

    Returns dict mapping (open_line, depth) -> parent's (open_line, depth) or None.
    """
    sorted_blocks = sorted(blocks, key=lambda b: b.open_line)
    active: dict[int, BracketBlock] = {}
    parent_map: dict[tuple[int, int], tuple[int, int] | None] = {}

    for b in sorted_blocks:
        for depth in sorted(active, reverse=True):
            if active[depth].close_line < b.open_line:
                del active[depth]

        if b.depth > 1 and (b.depth - 1) in active:
            parent = active[b.depth - 1]
            parent_map[(b.open_line, b.depth)] = (parent.open_line, parent.depth)
        else:
            parent_map[(b.open_line, b.depth)] = None

        active[b.depth] = b

    return parent_map
