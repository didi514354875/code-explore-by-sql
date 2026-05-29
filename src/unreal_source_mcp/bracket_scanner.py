"""Bracket skeleton scanner — lightweight structural indexing for C/C++ source.

Uses a finite state machine to track brace depth while correctly ignoring
braces inside comments, string literals, character literals, and raw strings.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# FSM states
CODE = 0
LINE_COMMENT = 1
BLOCK_COMMENT = 2
STRING = 3
CHAR_LITERAL = 4
RAW_STRING = 5


@dataclass(frozen=True)
class BracketBlock:
    open_line: int
    close_line: int
    depth: int
    is_complete: bool


def scan_brackets(content: str, lines: list[str] | None = None) -> list[BracketBlock]:
    """Scan content and return matched brace pairs with depth info.

    If lines is provided, skips the second split for callers that already
    split the content.
    """
    depth = 0
    stack: list[tuple[int, int]] = []  # (open_line, open_depth)
    blocks: list[BracketBlock] = []
    state = CODE
    raw_delim = ""

    if lines is None:
        lines = content.split("\n")
    last_line = len(lines)

    # Characters that could trigger a state transition or brace count.
    # Lines missing ALL of these can be skipped entirely — saves ~60-70% of lines.
    _TRIGGER_CHARS = frozenset('{}"/\'R')

    for line_idx, line in enumerate(lines, start=1):
        # Fast skip: if none of the trigger chars are present, this line
        # cannot affect brace depth or state machine. Only check if we're
        # in CODE state (other states may need to scan for closing markers).
        if state == CODE and not any(c in line for c in _TRIGGER_CHARS):
            continue

        i = 0
        n = len(line)
        while i < n:
            ch = line[i]
            next_ch = line[i + 1] if i + 1 < n else ""

            if state == CODE:
                if ch == "/" and next_ch == "/":
                    state = LINE_COMMENT
                    i += 2
                    continue
                if ch == "/" and next_ch == "*":
                    state = BLOCK_COMMENT
                    i += 2
                    continue
                if ch == "R" and next_ch == '"':
                    delim_end = line.find("(", i + 2)
                    if delim_end != -1:
                        raw_delim = line[i + 2 : delim_end]
                        state = RAW_STRING
                        i = delim_end + 1
                        continue
                if ch == '"':
                    state = STRING
                    i += 1
                    continue
                if ch == "'":
                    state = CHAR_LITERAL
                    i += 1
                    continue

                if ch == "{":
                    depth += 1
                    stack.append((line_idx, depth))
                elif ch == "}":
                    if stack:
                        open_line, open_depth = stack.pop()
                        blocks.append(
                            BracketBlock(
                                open_line=open_line,
                                close_line=line_idx,
                                depth=open_depth,
                                is_complete=True,
                            )
                        )
                    depth = max(0, depth - 1)

                i += 1

            elif state == LINE_COMMENT:
                break  # rest of line is comment

            elif state == BLOCK_COMMENT:
                if ch == "*" and next_ch == "/":
                    state = CODE
                    i += 2
                    continue
                i += 1

            elif state == STRING:
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    state = CODE
                i += 1

            elif state == CHAR_LITERAL:
                if ch == "\\":
                    i += 2
                    continue
                if ch == "'":
                    state = CODE
                i += 1

            elif state == RAW_STRING:
                end_marker = ")" + raw_delim + '"'
                pos = line.find(end_marker, i)
                if pos != -1:
                    state = CODE
                    i = pos + len(end_marker)
                    continue
                break  # continues on next line

        if state == LINE_COMMENT:
            state = CODE

    # Handle unclosed braces
    for open_line, open_depth in stack:
        blocks.append(
            BracketBlock(
                open_line=open_line,
                close_line=last_line,
                depth=open_depth,
                is_complete=False,
            )
        )

    return blocks
