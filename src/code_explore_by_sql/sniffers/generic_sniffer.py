"""Semantic-recursive C/C++ block classifier.

Classifies bracket-delimited blocks by language semantics, not brace depth.
A class block is explored for methods; a namespace for contained declarations.
Unclassifiable blocks are returned as None and simply not stored.

Layer 1: Generic C/C++ — namespace, class, struct, enum, function, method, macro_def
Layer 2: Project-specific (via provider) — ue_macro, ue_declare, etc.
"""

from __future__ import annotations

import re
from code_explore_by_sql.block_model import BlockInfo, BracketBlock, ExtraBlock
from code_explore_by_sql.providers.base import AbstractBlockProvider

# ── Regex constants ──────────────────────────────────────────────────────

_EXPORT_KEYWORDS = re.compile(
    r"\b(API|_API|PUBLIC|PRIVATE|MODULENAME_API|VISIBLE|HIDDEN)\b",
    re.IGNORECASE,
)

_NAMESPACE_RE = re.compile(r"\bnamespace\s+(\w+)")
_CLASS_RE = re.compile(
    r"\b(class|struct)\s+"
    r"(?:(?:__attribute__\s*\(\([^)]*\)\)|[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?)\s+)*"
    r"(\w+)",
)
_ENUM_RE = re.compile(r"\benum\s+(?:class\s+)?(\w+)")
_CONTROL_FLOW_RE = re.compile(
    r"\b(if|else\s+if|else|while|for|do|switch|catch|try)\b"
)
_FUNC_NAME_RE = re.compile(r"(\w+(?:\s*::\s*\w+)*)\s*\([^)]*\)\s*$")
_DEFINE_RE = re.compile(r"#\s*define\s+")
_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT_RE = re.compile(r"//[^\n]*")
_TEMPLATE_RE = re.compile(r"\btemplate\s*<[^<>]*>")
_BLOCK_KW_RE = re.compile(r"\b(class|struct|namespace|enum)\b")

# Member variable type extraction: TypeLetterCamelCase followed by pointer/ref and a name
_MEMBER_TYPE_RE = re.compile(
    r"\b([A-Z][A-Za-z0-9_]+)\s*[\*&]?\s+\w+\s*[;=]"
)

# Trailing modifiers to strip before function detection
_TRAILING_MODS_RE = re.compile(
    r"\s*(?:const|override|final|noexcept|mutable|constexpr|inline|static)\s*[;{]*\s*$"
)

# Destructor pattern
_DTOR_RE = re.compile(r"~(\w+)\s*\(")

# Operator overload pattern
_OPERATOR_RE = re.compile(
    r"\boperator(?:\s*[+\-*/%=<>!&|^~]+|\s*\(\)|\s*\[\]|\s*->|"
    r"\s*<<|\s*>>|\s*==|\s*!=|\s*<=|\s*>=|\s*&&|\s*\|\||\s*\+\+|\s*--)"
)

# extern "C" pattern
_EXTERN_C_RE = re.compile(r'\bextern\s+"C"')


# ── Helpers ──────────────────────────────────────────────────────────────

def _strip_comments(text: str) -> str:
    text = _BLOCK_COMMENT_RE.sub(" ", text)
    text = _LINE_COMMENT_RE.sub(" ", text)
    return text


def _strip_template(text: str) -> str:
    while True:
        new = _TEMPLATE_RE.sub(" ", text)
        if new == text:
            return text
        text = new


def _extract_function_name(signature: str) -> str | None:
    m = _FUNC_NAME_RE.search(signature)
    if m:
        name = m.group(1).strip()
        parts = name.split()
        parts = [p for p in parts if not _EXPORT_KEYWORDS.match(p)]
        return "::".join(p.strip() for p in " ".join(parts).split("::")) or None
    return None


def _gather_context(
    lines: list[str],
    open_line_0: int,
    skip_line_re: re.Pattern | None = None,
    max_lookback: int = 30,
) -> list[str]:
    """Gather non-empty, non-skipped lines preceding the opening brace."""
    context: list[str] = []
    # Include text on the same line as `{` (before the brace)
    open_text = lines[open_line_0].rstrip()
    if open_text.endswith("{"):
        open_text = open_text[:-1].rstrip()
    if open_text.strip():
        context.append(open_text.strip())

    # Back-scan for definition keyword or semicolon-terminated line
    def_start: int | None = None
    for j in range(open_line_0 - 1, max(open_line_0 - max_lookback, -1), -1):
        stripped = lines[j].strip()
        if not stripped or (skip_line_re and skip_line_re.match(stripped)):
            continue
        clean = _strip_comments(stripped).strip()
        if not clean:
            continue
        if clean.endswith(";"):
            break
        if _BLOCK_KW_RE.search(clean):
            def_start = j
            break

    preceding: list[str] = []
    if def_start is not None:
        for j in range(def_start, open_line_0):
            stripped = lines[j].strip()
            if not stripped or (skip_line_re and skip_line_re.match(stripped)):
                continue
            preceding.append(stripped)
    else:
        for j in range(open_line_0 - 1, max(open_line_0 - 10, -1), -1):
            stripped = lines[j].strip()
            if not stripped or (skip_line_re and skip_line_re.match(stripped)):
                continue
            preceding.insert(0, stripped)
            if len(preceding) >= 6:
                break

    return preceding + context


# ── Core classifier ──────────────────────────────────────────────────────

def _classify_block(
    lines: list[str],
    block: BracketBlock,
    skip_line_re: re.Pattern | None = None,
) -> BlockInfo | None:
    """Classify a single bracket block. Returns None if unclassifiable."""
    open_0 = block.open_line - 1  # convert to 0-based

    context = _gather_context(lines, open_0, skip_line_re)
    if not context:
        return None

    joined = " ".join(context)
    joined_clean = re.sub(r"\s+", " ", joined).strip()
    joined_clean = _strip_comments(joined_clean)
    joined_clean = _strip_template(joined_clean)
    joined_clean = re.sub(r"\s+", " ", joined_clean).strip()

    if not joined_clean:
        return None

    # 0. Preprocessor #define
    if any(_DEFINE_RE.match(line) for line in context):
        return BlockInfo("macro_def", None, joined_clean)

    # 1. extern "C" — treat as namespace-equivalent container
    if _EXTERN_C_RE.search(joined_clean):
        return BlockInfo("namespace", None, joined_clean)

    # 2. Namespace
    m = _NAMESPACE_RE.search(joined_clean)
    if m:
        return BlockInfo("namespace", m.group(1), joined_clean)

    # 3. Enum (before class since "enum class" contains "class")
    m = _ENUM_RE.search(joined_clean)
    if m:
        return BlockInfo("enum", m.group(1), joined_clean)

    # 4. Class / struct
    m = _CLASS_RE.search(joined_clean)
    if m:
        return BlockInfo("class", m.group(2), joined_clean)

    # 5. Function / method detection
    # Strip trailing modifiers to expose the closing `)`
    test_sig = _TRAILING_MODS_RE.sub("", joined_clean).rstrip()
    if test_sig.endswith(")"):
        # Check for destructor
        dtor = _DTOR_RE.search(test_sig)
        if dtor:
            return BlockInfo("function", dtor.group(1), joined_clean)
        # Check for control flow (skip)
        if _CONTROL_FLOW_RE.search(context[-1] if context else ""):
            return None
        name = _extract_function_name(test_sig)
        if name:
            return BlockInfo("function", name, joined_clean)

    # 6. Lambda detection: [...](...) pattern — skip
    if re.search(r"\[.*\]\s*[\(]", joined_clean):
        return None

    # Unclassifiable → None (not stored)
    return None


# ── Containment explorers ────────────────────────────────────────────────

def _blocks_inside(
    bracket_blocks: list[BracketBlock],
    parent: BracketBlock,
) -> list[tuple[int, BracketBlock]]:
    """Return (index, block) pairs for blocks physically inside parent."""
    result = []
    for i, b in enumerate(bracket_blocks):
        if b.open_line > parent.open_line and b.close_line < parent.close_line:
            result.append((i, b))
    return result


def _explore_class_interior(
    lines: list[str],
    bracket_blocks: list[BracketBlock],
    parent_idx: int,
    parent_info: BlockInfo,
    skip_line_re: re.Pattern | None,
    results: list[tuple[int, BlockInfo]],
) -> None:
    """Find methods and nested types inside a class/struct block."""
    parent = bracket_blocks[parent_idx]
    inner = _blocks_inside(bracket_blocks, parent)

    for child_idx, child_block in inner:
        info = _classify_block(lines, child_block, skip_line_re)
        if info is None:
            continue
        # Promote function → method when parent is class/struct
        if info.block_type == "function":
            info = BlockInfo(
                block_type="method",
                block_name=info.block_name,
                signature=info.signature,
                params=info.params,
                extra_fields=info.extra_fields,
            )
        results.append((child_idx, info))

        # Recurse into nested class/struct
        if info.block_type == "class":
            _explore_class_interior(
                lines, bracket_blocks, child_idx, info, skip_line_re, results,
            )


def _explore_namespace_interior(
    lines: list[str],
    bracket_blocks: list[BracketBlock],
    parent_idx: int,
    skip_line_re: re.Pattern | None,
    results: list[tuple[int, BlockInfo]],
) -> None:
    """Find classes, enums, functions inside a namespace block."""
    parent = bracket_blocks[parent_idx]
    inner = _blocks_inside(bracket_blocks, parent)

    for child_idx, child_block in inner:
        info = _classify_block(lines, child_block, skip_line_re)
        if info is None:
            continue
        results.append((child_idx, info))

        if info.block_type == "class":
            _explore_class_interior(
                lines, bracket_blocks, child_idx, info, skip_line_re, results,
            )
        elif info.block_type == "namespace":
            _explore_namespace_interior(
                lines, bracket_blocks, child_idx, skip_line_re, results,
            )


def _extract_member_types(
    lines: list[str],
    block: BracketBlock,
    skip_line_re: re.Pattern | None = None,
    known_types: set[str] | None = None,
) -> list[str]:
    """Scan class/struct body for member variable type dependencies."""
    body_start = block.open_line  # 1-based, line with {
    body_end = block.close_line   # 1-based, line with }
    types: list[str] = []
    for line_idx in range(body_start, body_end):
        line = lines[line_idx].strip()
        if not line:
            continue
        if skip_line_re and skip_line_re.match(line):
            continue
        # Skip lines that are access specifiers, comments, preprocessor
        if line.startswith("//") or line.startswith("/*") or line.startswith("#"):
            continue
        if line in ("public:", "private:", "protected:"):
            continue
        for m in _MEMBER_TYPE_RE.finditer(line):
            tname = m.group(1)
            if known_types and tname not in known_types:
                continue
            types.append(tname)
    return types


# ── Non-brace block extraction ───────────────────────────────────────────

def extract_preprocessor_blocks(lines: list[str]) -> list[ExtraBlock]:
    """Extract #define macros as non-brace blocks."""
    blocks: list[ExtraBlock] = []
    for i, line in enumerate(lines, start=1):
        stripped = line.strip()
        m = re.match(r"#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)", stripped)
        if m:
            name = m.group(1)
            params = m.group(2)  # e.g., "(x, y)" or None
            blocks.append(ExtraBlock(
                name=name,
                block_type="macro_def",
                start_line=i,
                end_line=i,
                params=params,
                signature=stripped,
            ))
    return blocks


# ── Public API ────────────────────────────────────────────────────────────

def sniff_semantic_blocks(
    lines: list[str],
    bracket_blocks: list[BracketBlock],
    provider: AbstractBlockProvider | None = None,
    known_types: set[str] | None = None,
) -> list[tuple[int, BlockInfo]]:
    """Classify blocks by language semantics with recursive containment.

    Returns list of (bracket_block_index, BlockInfo) for classified blocks only.
    Unclassifiable blocks are simply omitted.

    bracket_blocks: all BracketBlock objects from scan_brackets().
    provider: language/project-specific provider for line filtering and extra blocks.
    known_types: set of known type names for member type extraction filtering.
    """
    skip_re = provider.skip_line_re() if provider else None
    results: list[tuple[int, BlockInfo]] = []

    for i, block in enumerate(bracket_blocks):
        info = _classify_block(lines, block, skip_re)
        if info is None:
            continue
        results.append((i, info))

        # Explore interior based on containment semantics
        if info.block_type == "class":
            # Extract member types and attach as extra_fields
            member_types = _extract_member_types(lines, block, skip_re, known_types)
            if member_types:
                info = BlockInfo(
                    block_type=info.block_type,
                    block_name=info.block_name,
                    signature=info.signature,
                    params=info.params,
                    extra_fields={"member_types": list(set(member_types))},
                )
                results[-1] = (i, info)
            # Explore methods inside the class
            _explore_class_interior(lines, bracket_blocks, i, info, skip_re, results)

        elif info.block_type == "namespace":
            _explore_namespace_interior(lines, bracket_blocks, i, skip_re, results)

    return results


# ── Legacy API (backward compatibility) ───────────────────────────────────

def sniff_block(
    preceding_lines: list[str],
    open_line_idx: int,
    all_lines: list[str],
    skip_line_re: re.Pattern | None = None,
) -> BlockInfo:
    """Legacy: Classify a block by preceding lines. Returns BlockInfo("unknown",...) if unclassifiable."""
    context = []
    for line in preceding_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if skip_line_re and skip_line_re.match(stripped):
            continue
        context.append(stripped)

    if not context:
        return BlockInfo("unknown", None, None)

    joined = " ".join(context)
    joined_clean = re.sub(r"\s+", " ", joined).strip()
    joined_clean = _strip_comments(joined_clean)
    joined_clean = _strip_template(joined_clean)
    joined_clean = re.sub(r"\s+", " ", joined_clean).strip()

    if any(_DEFINE_RE.match(line) for line in context):
        return BlockInfo("macro_def", None, joined_clean)

    if _EXTERN_C_RE.search(joined_clean):
        return BlockInfo("namespace", None, joined_clean)

    m = _NAMESPACE_RE.search(joined_clean)
    if m:
        return BlockInfo("namespace", m.group(1), joined_clean)

    m = _ENUM_RE.search(joined_clean)
    if m:
        return BlockInfo("enum", m.group(1), joined_clean)

    m = _CLASS_RE.search(joined_clean)
    if m:
        return BlockInfo("class", m.group(2), joined_clean)

    test_sig = _TRAILING_MODS_RE.sub("", joined_clean).rstrip()
    if test_sig.endswith(")"):
        dtor = _DTOR_RE.search(test_sig)
        if dtor:
            return BlockInfo("function", dtor.group(1), joined_clean)
        if _CONTROL_FLOW_RE.search(context[-1] if context else ""):
            return BlockInfo("unknown", None, joined_clean)
        name = _extract_function_name(test_sig)
        if name:
            return BlockInfo("function", name, joined_clean)

    return BlockInfo("unknown", None, joined_clean)


def sniff_blocks_for_file(
    lines: list[str],
    top_blocks: list[tuple[int, int]],
    skip_line_re: re.Pattern | None = None,
) -> list[tuple[int, BlockInfo]]:
    """Legacy: Sniff depth=1 blocks only. Preserved for backward compatibility."""
    results = []
    for open_line, _close_line in top_blocks:
        open_0 = open_line
        context = _gather_context(lines, open_0, skip_line_re)
        info = sniff_block(context, open_0, lines, skip_line_re=skip_line_re)
        results.append((open_line, info))
    return results
