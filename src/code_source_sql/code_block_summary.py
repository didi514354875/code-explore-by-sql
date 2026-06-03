"""Code block summary strategies for the 'signature' view.

Reuses bracket_scanner for structural analysis and symbol_analyzer
helpers for declaration extraction. When DB child symbols are available,
skips text scanning and uses pre-classified symbol data directly.
"""

from __future__ import annotations

import re
from typing import Any

from .bracket_scanner import BracketBlock, compute_parent_map, scan_brackets
from .configs import FrameworkConfig, LanguageConfig, make_cpp_language, make_generic_framework
from .symbol_analyzer import _gather_declaration, _classify_block

# ── Defaults for text-only fallback path ─────────────────────────────────

_default_lang = make_cpp_language()
_default_fw = make_generic_framework()

# ── Regex patterns for function body summary ─────────────────────────────

_LOCAL_VAR_RE = re.compile(
    r"^\s*"
    r"(?:(?:const|static|mutable|constexpr|volatile)\s+)?"
    r"([A-Za-z_]\w*(?:\s*::\s*\w+)*(?:\s*<[^>]*>)?(?:\s*[*&]+)?)\s+"
    r"([A-Za-z_]\w*)"
    r"\s*(?:=[^;]*|)\s*;"
)

_RANGE_FOR_RE = re.compile(
    r"for\s*\(\s*(?:const\s+)?(\w+(?:\s*<[^>]*>)?)\s*[*&]?\s+(\w+)\s*:\s*(\w+)"
)

_CONTROL_FLOW_RES = [
    (re.compile(r"^\s*for\s*\((.{1,80})\)\s*\{?\s*$"), "for"),
    (re.compile(r"^\s*while\s*\((.{1,80})\)\s*\{?\s*$"), "while"),
    (re.compile(r"^\s*(?:else\s+)?if\s*\((.{1,80})\)\s*\{?\s*$"), "if"),
    (re.compile(r"^\s*switch\s*\((.{1,40})\)\s*\{?\s*$"), "switch"),
]

_RETURN_RE = re.compile(r"^\s*return\s+(.{1,60});")

# Access specifiers (C++)
_ACCESS_SPEC_RE = re.compile(r"^\s*(?:public|private|protected)\s*:\s*(?://.*)?$")

# UE decoration macros to keep in class summary
_UE_MACRO_RE = re.compile(r"^\s*(UFUNCTION|UPROPERTY|UCLASS|USTRUCT|UPARAM|UMETA)\b")

# ── Dispatcher ───────────────────────────────────────────────────────────

_CLASS_TYPES = frozenset({"class", "namespace"})
_FUNC_TYPES = frozenset({"method", "function"})
_MACRO_TYPES = frozenset({"macro_def"})
_DECL_TYPES = frozenset({"enum", "delegate_def"})


def apply_view(
    code: str,
    view: str,
    *,
    block_type: str | None = None,
    qualified_name: str | None = None,
    child_symbols: list[dict[str, Any]] | None = None,
) -> str:
    if view == "full":
        return code
    if view == "meta":
        return ""
    if view != "signature":
        return code

    if not code or not code.strip():
        return code

    strategy = _pick_strategy(block_type, code)

    if strategy == "class":
        return summarize_class_block(code, child_symbols=child_symbols)
    if strategy == "function":
        return summarize_function_body(code)
    if strategy == "macro":
        return summarize_macro_block(code)

    return code


def _pick_strategy(block_type: str | None, code: str) -> str:
    if block_type:
        if block_type in _CLASS_TYPES:
            return "class"
        if block_type in _FUNC_TYPES:
            return "function"
        if block_type in _MACRO_TYPES:
            return "macro"
        if block_type in _DECL_TYPES:
            return "declaration"

    for line in code.split("\n"):
        s = line.strip()
        if not s or s.startswith("//") or s.startswith("/*"):
            continue
        if re.search(r"\b(?:class|struct)\b", s):
            return "class"
        if s.startswith("#") and "define" in s:
            return "macro"
        if "(" in s and ")" in s:
            return "function"
        break

    return "unknown"


# ── Strategy 1: Class / struct / namespace ───────────────────────────────

def summarize_class_block(
    code: str,
    *,
    child_symbols: list[dict[str, Any]] | None = None,
    lang: LanguageConfig | None = None,
    fw: FrameworkConfig | None = None,
) -> str:
    if child_symbols is not None:
        return _class_summary_from_symbols(code, child_symbols)
    return _class_summary_from_text(code, lang or _default_lang, fw or _default_fw)


def _class_summary_from_symbols(
    code: str,
    child_symbols: list[dict[str, Any]],
) -> str:
    lines = code.split("\n")
    total = len(lines)

    child_by_start: dict[int, dict] = {}
    for sym in child_symbols:
        child_by_start[sym["start_line"]] = sym

    kept: list[str] = []

    for i, line in enumerate(lines, start=1):
        stripped = line.strip()

        if stripped in ("public:", "protected:", "private:"):
            kept.append(line)
            continue

        if _UE_MACRO_RE.match(stripped):
            kept.append(line)
            continue

        child = child_by_start.get(i)
        if child:
            btype = child["block_type"]
            if btype in _FUNC_TYPES:
                sig = child.get("signature") or _declaration_from_code(lines, i - 1)
                if sig:
                    kept.append(f"  {sig};")
                else:
                    kept.append(line)
                continue
            if btype in _CLASS_TYPES:
                kept.append(line)
                kept.append(f"  // ... {btype} {child.get('qualified_name', '')} ...")
                kept.append("};")
                continue
            if btype == "enum":
                kept.append(line)
                continue
            kept.append(line)
            continue

        if i in child_by_start:
            continue

        if not _is_inside_child_block(i, child_by_start):
            if ";" in stripped and not stripped.startswith("//"):
                kept.append(line)

    kept.append(f"// ... {total} lines total")
    return "\n".join(kept)


def _declaration_from_code(lines: list[str], line_idx_0: int) -> str | None:
    start = line_idx_0
    while start > 0 and lines[start - 1].strip().startswith("//"):
        start -= 1
    for j in range(start, min(start + 6, len(lines))):
        if "{" in lines[j]:
            decl = " ".join(l.strip() for l in lines[start:j + 1])
            brace_pos = decl.find("{")
            if brace_pos > 0:
                return decl[:brace_pos].rstrip()
            return decl
    return None


def _is_inside_child_block(
    line_1based: int,
    child_by_start: dict[int, dict],
) -> bool:
    for start, sym in child_by_start.items():
        end = sym.get("end_line", start)
        if start < line_1based <= end:
            if sym["block_type"] in _FUNC_TYPES:
                return True
            if sym["block_type"] in _CLASS_TYPES:
                return start < line_1based < end
    return False


def _class_summary_from_text(
    code: str,
    lang: LanguageConfig,
    fw: FrameworkConfig,
) -> str:
    blocks = scan_brackets(code)
    if not blocks:
        return code

    parent_map = compute_parent_map(blocks)
    lines = code.split("\n")

    outermost = min(blocks, key=lambda b: b.depth)
    outer_depth = outermost.depth
    outer_key = (outermost.open_line, outermost.depth)

    child_blocks: list[BracketBlock] = []
    for blk in blocks:
        if blk is outermost:
            continue
        key = (blk.open_line, blk.depth)
        p = parent_map.get(key)
        if p == outer_key:
            child_blocks.append(blk)

    child_lines: set[int] = set()
    for blk in child_blocks:
        for ln in range(blk.open_line, blk.close_line + 1):
            child_lines.add(ln)

    kept: list[str] = []
    for i, line in enumerate(lines, start=1):
        stripped = line.strip()

        if i <= outermost.open_line:
            kept.append(line)
            continue

        if i >= outermost.close_line:
            kept.append(line)
            continue

        if stripped in ("public:", "protected:", "private:"):
            kept.append(line)
            continue

        if _UE_MACRO_RE.match(stripped):
            kept.append(line)
            continue

        if i in child_lines:
            for blk in child_blocks:
                if blk.open_line == i:
                    decl_lines = _gather_declaration(lines, i - 1, lang, fw)
                    if decl_lines:
                        decl = " ".join(decl_lines).rstrip()
                        brace_pos = decl.find("{")
                        if brace_pos > 0:
                            decl = decl[:brace_pos].rstrip()
                        kept.append(f"  {decl};")
                    else:
                        kept.append(line)
            continue

        if ";" in stripped and not stripped.startswith("//"):
            kept.append(line)

    kept.append(f"// ... {len(lines)} lines total")
    return "\n".join(kept)


# ── Strategy 2: Macro definitions ───────────────────────────────────────

def summarize_macro_block(code: str) -> str:
    blocks = scan_brackets(code)
    if not blocks:
        return _macro_fallback(code)

    parent_map = compute_parent_map(blocks)
    lines = code.split("\n")

    if blocks:
        outermost = min(blocks, key=lambda b: b.depth)
    else:
        return code

    outer_key = (outermost.open_line, outermost.depth)

    child_blocks: list[BracketBlock] = []
    for blk in blocks:
        if blk is outermost:
            continue
        key = (blk.open_line, blk.depth)
        p = parent_map.get(key)
        if p == outer_key:
            child_blocks.append(blk)

    child_lines: set[int] = set()
    for blk in child_blocks:
        for ln in range(blk.open_line, blk.close_line + 1):
            child_lines.add(ln)

    kept: list[str] = []
    for i, line in enumerate(lines, start=1):
        stripped = line.strip()

        if i <= outermost.open_line:
            kept.append(line)
            continue
        if i >= outermost.close_line:
            kept.append(line)
            continue

        if i in child_lines:
            for blk in child_blocks:
                if blk.open_line == i:
                    decl_lines = _gather_declaration(lines, i - 1, _default_lang, _default_fw)
                    if decl_lines:
                        decl = " ".join(decl_lines).rstrip()
                        brace_pos = decl.find("{")
                        if brace_pos > 0:
                            decl = decl[:brace_pos].rstrip()
                        kept.append(f"  {decl};")
                    else:
                        kept.append(line)
            continue

        if ";" in stripped and not stripped.startswith("//"):
            kept.append(line)

    kept.append(f"// ... {len(lines)} lines total")
    return "\n".join(kept)


def _macro_fallback(code: str) -> str:
    lines = code.split("\n")
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if ";" in stripped:
            kept.append(line)
    kept.append(f"// ... {len(lines)} lines total")
    return "\n".join(kept)


# ── Strategy 3: Function body ───────────────────────────────────────────

def summarize_function_body(code: str) -> str:
    lines = code.split("\n")

    brace_idx = _find_first_open_brace(lines)
    if brace_idx < 0:
        return code

    sig_lines = lines[: brace_idx + 1]
    body_lines = lines[brace_idx + 1 :]

    summary_lines: list[str] = list(sig_lines)

    body_content = "\n".join(body_lines)
    body_stripped = body_content.strip()

    if not body_stripped or body_stripped == "}":
        return code

    for line in body_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped in ("{", "}", "{})", "};"):
            continue

        m = _LOCAL_VAR_RE.match(stripped)
        if m:
            vtype = m.group(1).strip()
            vname = m.group(2)
            init_match = re.search(r"=\s*([^;]+);", stripped)
            if init_match:
                init_val = init_match.group(1).strip()
                if len(init_val) > 40:
                    init_val = init_val[:37] + "..."
                summary_lines.append(f"  {vtype} {vname} = {init_val};")
            else:
                summary_lines.append(f"  {vtype} {vname};")
            continue

        rf = _RANGE_FOR_RE.search(stripped)
        if rf:
            vtype, vname, container = rf.group(1), rf.group(2), rf.group(3)
            summary_lines.append(f"  for ({vtype} {vname} : {container}) {{ ... }}")
            continue

        matched_flow = False
        for pat, kw in _CONTROL_FLOW_RES:
            m = pat.match(line)
            if m:
                cond = m.group(1).strip()
                if len(cond) > 60:
                    cond = cond[:57] + "..."
                summary_lines.append(f"  {kw} ({cond}) {{ ... }}")
                matched_flow = True
                break
        if matched_flow:
            continue

        rm = _RETURN_RE.match(stripped)
        if rm:
            retval = rm.group(1).strip()
            if len(retval) > 60:
                retval = retval[:57] + "..."
            summary_lines.append(f"  return {retval};")
            continue

    closing = _find_closing_brace(body_lines)
    if closing is not None:
        summary_lines.append(closing)

    body_count = len(body_lines)
    summary_lines.append(f"// ... {body_count} lines in body")

    return "\n".join(summary_lines)


def _find_first_open_brace(lines: list[str]) -> int:
    depth = 0
    for i, line in enumerate(lines):
        for ch in line:
            if ch == "{":
                if depth == 0:
                    return i
                depth += 1
            elif ch == "}":
                depth -= 1
    return -1


def _find_closing_brace(lines: list[str]) -> str | None:
    for line in reversed(lines):
        s = line.strip()
        if s.startswith("}"):
            return line
    return None
