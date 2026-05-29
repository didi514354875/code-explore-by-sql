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
# Allows zero or more qualifiers between class/struct and the name:
#   - __attribute__((...))
#   - UPPER_CASE token, optionally with parenthesized args (e.g. UE_DEPRECATED(5.7, "msg"))
# This deliberately excludes camelCase / PascalCase tokens so the real name
# isn't swallowed as an export macro.
_CLASS_RE = re.compile(
    r"\b(class|struct)\s+"
    r"(?:(?:__attribute__\s*\(\([^)]*\)\)|[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?)\s+)*"
    r"(\w+)",
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

# Block-defining keywords used to locate the actual definition line in
# sniff_blocks_for_file (excludes forward-decl-only contexts).
_BLOCK_KW_RE = re.compile(r"\b(class|struct|namespace|enum)\b")

# Block / line comment stripping
_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT_RE = re.compile(r"//[^\n]*")
_TEMPLATE_RE = re.compile(r"\btemplate\s*<[^<>]*>")


def _strip_comments(text: str) -> str:
    """Remove C/C++ block and line comments from a string."""
    text = _BLOCK_COMMENT_RE.sub(" ", text)
    text = _LINE_COMMENT_RE.sub(" ", text)
    return text


def _strip_template(text: str) -> str:
    """Remove `template<...>` prefixes (handles up to 1 level of nested <>)."""
    while True:
        new = _TEMPLATE_RE.sub(" ", text)
        if new == text:
            return text
        text = new


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
    # Strip comments and template<...> prefixes so the regexes below see
    # only structural code tokens.
    joined_clean = _strip_comments(joined_clean)
    joined_clean = _strip_template(joined_clean)
    joined_clean = re.sub(r"\s+", " ", joined_clean).strip()

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

        # Locate the actual definition start by scanning backwards for a line
        # that contains a class/struct/namespace/enum keyword and is not a
        # forward declaration (does not end with ';').  Stop at any forward
        # declaration we encounter so neighbouring forward decls are excluded.
        def_start: int | None = None
        for j in range(open_line - 1, max(open_line - 20, -1), -1):
            _, txt = stripped_lines[j]
            stripped = txt.strip()
            if not stripped or _UE_MACRO_RE.match(stripped):
                continue
            stripped_no_cmt = _strip_comments(stripped).strip()
            if not stripped_no_cmt:
                continue
            if stripped_no_cmt.endswith(";"):
                # Forward declaration / unrelated statement — stop.
                break
            if _BLOCK_KW_RE.search(stripped_no_cmt):
                def_start = j
                break

        preceding: list[str] = []
        if def_start is not None:
            # Collect lines from def_start up to (but excluding) open_line.
            for j in range(def_start, open_line):
                _, txt = stripped_lines[j]
                stripped = txt.strip()
                if not stripped or _UE_MACRO_RE.match(stripped):
                    continue
                preceding.append(stripped)
        else:
            # Fallback (functions / control flow / unknown blocks):
            # collect up to 5 non-blank, non-UE-macro lines preceding open_line.
            for j in range(open_line - 1, max(open_line - 20, -1), -1):
                _, txt = stripped_lines[j]
                stripped = txt.strip()
                if not stripped or _UE_MACRO_RE.match(stripped):
                    continue
                preceding.insert(0, stripped)
                if len(preceding) >= 5:
                    break

        # Append open_line declaration text
        if open_text.strip():
            preceding.append(open_text.strip())

        info = sniff_block(preceding, open_line, lines)
        results.append((open_line, info))

    return results
