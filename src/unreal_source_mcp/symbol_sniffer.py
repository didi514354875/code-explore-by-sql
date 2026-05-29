"""Symbol header sniffer — heuristic block-type classification for C/C++.

Analyses the lines preceding a top-level `{` to determine whether the block
is a namespace, class, enum, function, control-flow construct, or macro.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# UE macros to skip when looking for block-type keywords
UE_SKIP_MACROS = frozenset(
    {
        "UCLASS",
        "USTRUCT",
        "UENUM",
        "UPROPERTY",
        "UFUNCTION",
        "GENERATED_BODY",
        "GENERATED_UCLASS_BODY",
        "GENERATED_USTRUCT_BODY",
        "UMETA",
        "UPARAM",
        "UINTERFACE",
        "BEGIN_SLATE_FUNCTION_BUILD_OPTIMIZATION",
        "END_SLATE_FUNCTION_BUILD_OPTIMIZATION",
    }
)

# Pattern matching UE macro lines like UCLASS(), UPROPERTY() etc.
_UE_MACRO_RE = re.compile(
    r"^\s*(" + "|".join(re.escape(m) for m in UE_SKIP_MACROS) + r")\s*\("
)

# Export / visibility specifiers to strip when extracting names
_EXPORT_KEYWORDS = re.compile(
    r"\b(API|_API|PUBLIC|PRIVATE|MODULENAME_API|VISIBLE|HIDDEN)\b",
    re.IGNORECASE,
)

# Namespace pattern
_NAMESPACE_RE = re.compile(r"\bnamespace\s+(\w+)")

# Class/struct pattern (handles final, alignas, attributes, export macros)
_CLASS_RE = re.compile(
    r"\b(class|struct)\s+"
    r"(?:__attribute__\([^)]*\)\s*)?"  # optional __attribute__
    r"(?:\w+\s+)?"  # optional export macro like MYMODULE_API
    r"(\w+)",  # the name
    re.IGNORECASE,
)

# Enum pattern
_ENUM_RE = re.compile(r"\benum\s+(?:class\s+)?(\w+)")

# Control-flow keywords
_CONTROL_FLOW_RE = re.compile(
    r"\b(if|else\s+if|else|while|for|do|switch|catch|try)\b"
)

# Function name extraction: last identifier before `(`
_FUNC_NAME_RE = re.compile(r"(\w+(?:\s*::\s*\w+)*)\s*\([^)]*\)\s*$")

# Preprocessor define
_DEFINE_RE = re.compile(r"#\s*define\s+")


@dataclass(frozen=True)
class BlockInfo:
    block_type: str  # namespace, class, enum, function, control_flow, macro, unknown
    block_name: str | None
    signature: str | None


def sniff_block(
    preceding_lines: list[str], open_line_idx: int, all_lines: list[str]
) -> BlockInfo:
    """Classify a top-level block by examining preceding lines.

    preceding_lines: lines before the `{` (most recent last), already stripped
                     of UE macros and blank lines.
    open_line_idx:    0-based index of the `{` line in all_lines.
    all_lines:        full file lines (0-based) for context if needed.
    """
    # Filter out UE macro lines and blank lines from preceding context
    context = []
    for line in preceding_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if _UE_MACRO_RE.match(stripped):
            continue
        context.append(stripped)

    if not context:
        return BlockInfo("unknown", None, None)

    # Join context into a single string for pattern matching
    joined = " ".join(context)
    # Collapse whitespace
    joined_clean = re.sub(r"\s+", " ", joined).strip()

    # 0. Preprocessor define (must be first — #define FOO() looks like a function)
    if any(_DEFINE_RE.match(line) for line in context):
        return BlockInfo("macro", None, joined_clean)

    # 1. Namespace
    m = _NAMESPACE_RE.search(joined_clean)
    if m:
        return BlockInfo("namespace", m.group(1), joined_clean)

    # 2. Enum (check before class since "enum class" contains "class")
    m = _ENUM_RE.search(joined_clean)
    if m:
        return BlockInfo("enum", m.group(1), joined_clean)

    # 3. Class / struct
    m = _CLASS_RE.search(joined_clean)
    if m:
        name = m.group(2)
        return BlockInfo("class", name, joined_clean)

    # 4. Function (ends with `)` before `{`)
    if joined_clean.endswith(")"):
        # Check it's not control flow
        if not _CONTROL_FLOW_RE.search(context[-1] if context else ""):
            name = _extract_function_name(joined_clean)
            return BlockInfo("function", name, joined_clean)

    # 5. Control flow
    if _CONTROL_FLOW_RE.search(context[-1] if context else ""):
        return BlockInfo("control_flow", None, joined_clean)

    return BlockInfo("unknown", None, joined_clean)


def _extract_function_name(signature: str) -> str | None:
    """Extract function name from a signature ending with `)`."""
    m = _FUNC_NAME_RE.search(signature)
    if m:
        name = m.group(1).strip()
        # Remove export macros from name
        parts = name.split()
        parts = [p for p in parts if not _EXPORT_KEYWORDS.match(p)]
        return "::".join(p.strip() for p in " ".join(parts).split("::")) or None
    return None


def sniff_blocks_for_file(
    lines: list[str], top_blocks: list[tuple[int, int]]
) -> list[tuple[int, BlockInfo]]:
    """Sniff all top-level blocks in a file.

    lines: all lines of the file (0-based indexing).
    top_blocks: list of (open_line_0based, close_line_0based) for each depth=1 block.

    Returns list of (open_line_0based, BlockInfo).
    """
    results = []
    # Pre-strip and pre-classify lines to avoid repeated work
    stripped_lines = [
        (i, ln.rstrip()) for i, ln in enumerate(lines)
    ]

    for open_line, _close_line in top_blocks:
        # Get the open_line text (before the '{')
        _, open_text = stripped_lines[open_line]
        if open_text.endswith("{"):
            open_text = open_text[:-1].rstrip()

        # Collect preceding lines — only need up to 5 non-blank, non-UE-macro
        preceding: list[str] = []
        for j in range(open_line - 1, max(open_line - 20, -1), -1):
            if j < 0:
                break
            _, txt = stripped_lines[j]
            if not txt:
                continue
            if _UE_MACRO_RE.match(txt):
                continue
            preceding.insert(0, txt)
            if len(preceding) >= 5:
                break

        # Append open_line declaration text
        if open_text.strip():
            preceding.append(open_text)

        info = sniff_block(preceding, open_line, lines)
        results.append((open_line, info))

    return results
