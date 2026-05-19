from __future__ import annotations

import re
from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class CodeChunk:
    symbol_name: str | None
    symbol_type: str
    signature: str
    body: str
    start_line: int
    end_line: int
    comment: str | None = None
    extraction_method: str = "heuristic"


_FUNCTION_RE = re.compile(
    r"^\s*(?:(?:template\s*<[^;{}]+>\s*)|(?:FORCEINLINE\s+|UE_NODISCARD\s+|static\s+|virtual\s+|inline\s+|explicit\s+|constexpr\s+))*"
    r"[~\w:\<\>\*&\s,]+\s+([A-Za-z_]\w*::[~A-Za-z_]\w*)\s*\([^;{}]*\)\s*(?:const\s*)?(?:noexcept\s*)?(?:->\s*[^{}]+)?\s*(?:\{|$)"
)
_CLASS_RE = re.compile(r"^\s*(?:UCLASS\([^)]*\)\s*)?(?:class|struct)\s+(?:\w+_API\s+)?([A-Za-z_]\w*)\b.*(?:\{|$)")
_MACRO_RE = re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)")


def extract_chunks(content: str, symbol: str | None = None) -> list[CodeChunk]:
    lines = content.splitlines()
    chunks: list[CodeChunk] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        macro = _MACRO_RE.match(line)
        if macro:
            start, end = _extract_macro(lines, i)
            name = macro.group(1)
            if _matches_symbol(name, symbol):
                chunks.append(_make_chunk(lines, start, end, name, "Macro"))
            i = end + 1
            continue

        function = _FUNCTION_RE.match(line)
        if function:
            brace_line = _find_open_brace_line(lines, i)
            if brace_line is not None:
                end = _find_matching_brace(lines, brace_line)
                if end is not None:
                    name = function.group(1)
                    if _matches_symbol(name, symbol):
                        start = _signature_start(lines, i)
                        chunks.append(_make_chunk(lines, start, end, name, "Function"))
                    i = end + 1
                    continue

        klass = _CLASS_RE.match(line)
        if klass:
            brace_line = _find_open_brace_line(lines, i)
            if brace_line is not None:
                end = _find_matching_brace(lines, brace_line)
                if end is not None:
                    name = klass.group(1)
                    if _matches_symbol(name, symbol):
                        start = _signature_start(lines, i)
                        chunks.append(_make_chunk(lines, start, end, name, "Class"))
                    i = end + 1
                    continue
        i += 1
    return chunks


def chunk_to_dict(chunk: CodeChunk) -> dict[str, object]:
    return asdict(chunk)


def _matches_symbol(name: str, symbol: str | None) -> bool:
    if not symbol:
        return True
    needle = symbol.lower()
    return needle in name.lower() or needle in name.split("::")[-1].lower()


def _extract_macro(lines: list[str], start: int) -> tuple[int, int]:
    end = start
    while end + 1 < len(lines) and lines[end].rstrip().endswith("\\"):
        end += 1
    return start, end


def _find_open_brace_line(lines: list[str], start: int, max_scan: int = 12) -> int | None:
    for i in range(start, min(len(lines), start + max_scan)):
        if _first_code_brace_index(lines[i]) is not None:
            return i
        stripped = lines[i].strip()
        if stripped.endswith(";"):
            return None
    return None


def _signature_start(lines: list[str], anchor: int) -> int:
    start = anchor
    while start > 0:
        prev = lines[start - 1].strip()
        if not prev:
            break
        if prev.startswith(("//", "/*", "*", "*/", "UFUNCTION", "UPROPERTY", "UCLASS", "USTRUCT", "template")):
            start -= 1
            continue
        if lines[start - 1].rstrip().endswith((",", "(", "::", "<")):
            start -= 1
            continue
        break
    return start


def _make_chunk(lines: list[str], start: int, end: int, name: str, kind: str) -> CodeChunk:
    body = "\n".join(lines[start : end + 1])
    signature_lines = []
    for line in lines[start : min(end + 1, start + 20)]:
        signature_lines.append(line.strip())
        if "{" in line or kind == "Macro":
            break
    comment = _leading_comment(lines, start)
    return CodeChunk(
        symbol_name=name,
        symbol_type=kind,
        signature=" ".join(part for part in signature_lines if part),
        body=body,
        start_line=start + 1,
        end_line=end + 1,
        comment=comment,
    )


def _leading_comment(lines: list[str], start: int) -> str | None:
    comments: list[str] = []
    i = start - 1
    while i >= 0:
        stripped = lines[i].strip()
        if stripped.startswith(("//", "/*", "*", "*/")):
            comments.append(lines[i])
            i -= 1
            continue
        if not stripped and comments:
            break
        break
    if not comments:
        return None
    return "\n".join(reversed(comments))


def _find_matching_brace(lines: list[str], start_line: int) -> int | None:
    depth = 0
    seen_open = False
    state = "code"
    raw_delim: str | None = None

    for line_index in range(start_line, len(lines)):
        line = lines[line_index]
        i = 0
        while i < len(line):
            ch = line[i]
            nxt = line[i + 1] if i + 1 < len(line) else ""

            if state == "line_comment":
                break
            if state == "block_comment":
                if ch == "*" and nxt == "/":
                    state = "code"
                    i += 2
                    continue
                i += 1
                continue
            if state == "string":
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    state = "code"
                i += 1
                continue
            if state == "char":
                if ch == "\\":
                    i += 2
                    continue
                if ch == "'":
                    state = "code"
                i += 1
                continue
            if state == "raw_string":
                end_token = ")" + (raw_delim or "") + '"'
                if line.startswith(end_token, i):
                    state = "code"
                    i += len(end_token)
                    continue
                i += 1
                continue

            if ch == "/" and nxt == "/":
                state = "line_comment"
                break
            if ch == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if ch == "R" and nxt == '"':
                open_paren = line.find("(", i + 2)
                if open_paren != -1:
                    raw_delim = line[i + 2 : open_paren]
                    state = "raw_string"
                    i = open_paren + 1
                    continue
            if ch == '"':
                state = "string"
                i += 1
                continue
            if ch == "'":
                state = "char"
                i += 1
                continue
            if ch == "{":
                depth += 1
                seen_open = True
            elif ch == "}":
                depth -= 1
                if seen_open and depth == 0:
                    return line_index
            i += 1
        if state == "line_comment":
            state = "code"
    return None


def _first_code_brace_index(line: str) -> int | None:
    state = "code"
    i = 0
    while i < len(line):
        ch = line[i]
        nxt = line[i + 1] if i + 1 < len(line) else ""
        if state == "string":
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                state = "code"
            i += 1
            continue
        if ch == "/" and nxt in {"/", "*"}:
            return None
        if ch == '"':
            state = "string"
        elif ch == "{":
            return i
        i += 1
    return None
