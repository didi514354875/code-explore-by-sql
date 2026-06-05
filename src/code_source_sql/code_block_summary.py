"""Code block summary strategies for the 'signature' view.

Reuses bracket_scanner for structural analysis and symbol_analyzer
helpers for declaration extraction. When DB child symbols are available,
skips text scanning and uses pre-classified symbol data directly.

All regex patterns are sourced from LanguageConfig and FrameworkConfig
rather than hardcoded.
"""

from __future__ import annotations

import re
from typing import Any

from .bracket_scanner import BracketBlock, compute_parent_map, scan_brackets
from .configs import FrameworkConfig, LanguageConfig
from .symbol_analyzer import _gather_declaration


def _is_comment_or_empty(s: str, lang: LanguageConfig) -> bool:
    """Check if a stripped line is empty, a line comment, or starts a block comment."""
    if not s:
        return True
    if lang.line_comment and s.startswith(lang.line_comment):
        return True
    if lang.block_comment_pair and s.startswith(lang.block_comment_pair[0]):
        return True
    return False


def _format_control_flow(lang: LanguageConfig, kw: str, cond: str) -> str:
    """Format a control flow summary line based on language brace style."""
    if lang.uses_braces:
        return f"  {kw} ({cond}) {{ ... }}"
    return f"  {kw} {cond}: ..."


# ── Dispatcher ───────────────────────────────────────────────────────────

_CLASS_TYPES = frozenset({"class", "namespace"})
_FUNC_TYPES = frozenset({"method", "function"})
_MACRO_TYPES = frozenset({"macro_def"})
_DECL_TYPES = frozenset({"enum", "delegate_def"})


_MAX_TRUNCATE_SUFFIX = "// ... truncated, {total} lines total"


def _truncate_lines(lines: list[str], max_lines: int) -> list[str]:
    """Truncate result lines to max_lines, appending truncation notice if needed."""
    if max_lines <= 0 or len(lines) <= max_lines:
        return lines
    return lines[: max_lines - 1] + [_MAX_TRUNCATE_SUFFIX.format(total=len(lines))]


def apply_view(
    code: str,
    view: str,
    *,
    block_type: str | None = None,
    qualified_name: str | None = None,
    child_symbols: list[dict[str, Any]] | None = None,
    lang: LanguageConfig | None = None,
    fw: FrameworkConfig | None = None,
    max_lines: int = 0,
) -> str:
    if view == "full":
        return code
    if view == "meta":
        return ""
    if view != "signature":
        return code

    if not code or not code.strip():
        return code

    # For signature view, ensure we have a language config
    if lang is None:
        from .configs import make_cpp_language
        lang = make_cpp_language()
    if fw is None:
        from .configs import make_generic_framework
        fw = make_generic_framework()

    strategy = _pick_strategy(block_type, code, lang)

    if strategy == "class":
        result = summarize_class_block(code, child_symbols=child_symbols, lang=lang, fw=fw)
    elif strategy == "function":
        result = summarize_function_body(code, lang=lang)
    elif strategy == "macro":
        result = summarize_macro_block(code, lang=lang, fw=fw)
    else:
        return code

    if max_lines > 0:
        result_lines = result.split("\n")
        result_lines = _truncate_lines(result_lines, max_lines)
        return "\n".join(result_lines)
    return result


def _pick_strategy(block_type: str | None, code: str, lang: LanguageConfig) -> str:
    if block_type:
        if block_type in _CLASS_TYPES:
            return "class"
        if block_type in _FUNC_TYPES:
            return "function"
        if block_type in _MACRO_TYPES:
            return "macro"
        if block_type in _DECL_TYPES:
            return "declaration"

    block_kw_re = lang.block_keyword_re or re.compile(r"\b(?:class|struct)\b")

    for line in code.split("\n"):
        s = line.strip()
        if _is_comment_or_empty(s, lang):
            continue
        if block_kw_re.search(s):
            return "class"
        if lang.preprocessor_prefix and s.startswith(lang.preprocessor_prefix) and "define" in s:
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
        return _class_summary_from_symbols(code, child_symbols, lang, fw)
    return _class_summary_from_text(code, lang, fw)


def _class_summary_from_symbols(
    code: str,
    child_symbols: list[dict[str, Any]],
    lang: LanguageConfig,
    fw: FrameworkConfig,
) -> str:
    lines = code.split("\n")
    total = len(lines)

    child_by_start: dict[int, dict] = {}
    for sym in child_symbols:
        child_by_start[sym["start_line"]] = sym

    # Get config-driven patterns
    access_spec_names = lang.access_spec_names
    deco_macro_re = fw.decoration_macro_re

    kept: list[str] = []

    for i, line in enumerate(lines, start=1):
        stripped = line.strip()

        if stripped in access_spec_names:
            kept.append(line)
            continue

        if deco_macro_re and deco_macro_re.match(stripped):
            kept.append(line)
            continue

        child = child_by_start.get(i)
        if child:
            btype = child["block_type"]
            if btype in _FUNC_TYPES:
                sig = child.get("signature") or _declaration_from_code(lines, i - 1, lang)
                if sig:
                    kept.append(f"  {sig};")
                else:
                    kept.append(line)
                continue
            if btype in _CLASS_TYPES:
                kept.append(line)
                kept.append(f"  {lang.summary_comment_prefix} ... {btype} {child.get('qualified_name', '')} ...")
                kept.append(lang.block_close_suffix)
                continue
            if btype == "enum":
                kept.append(line)
                continue
            kept.append(line)
            continue

        if i in child_by_start:
            continue

        if not _is_inside_child_block(i, child_by_start):
            if (
                lang.statement_terminator and lang.statement_terminator in stripped
            ) and not _is_comment_or_empty(stripped, lang):
                kept.append(line)

    kept.append(f"{lang.summary_comment_prefix} ... {total} lines total")
    return "\n".join(kept)


def _declaration_from_code(lines: list[str], line_idx_0: int, lang: LanguageConfig | None = None) -> str | None:
    start = line_idx_0
    while start > 0 and lines[start - 1].strip().startswith(lang.line_comment if lang else "//"):
        start -= 1
    for j in range(start, min(start + 6, len(lines))):
        if "{" in lines[j]:
            decl = " ".join(ln.strip() for ln in lines[start:j + 1])
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
    blocks = scan_brackets(
        code,
        verbatim_string_prefix=lang.verbatim_string_prefix,
        raw_string_char=lang.raw_string_char,
    )
    if not blocks:
        return code

    parent_map = compute_parent_map(blocks)
    lines = code.split("\n")

    # Get config-driven patterns
    access_spec_names = lang.access_spec_names
    deco_macro_re = fw.decoration_macro_re

    outermost = min(blocks, key=lambda b: b.depth)
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

        if stripped in access_spec_names:
            kept.append(line)
            continue

        if deco_macro_re and deco_macro_re.match(stripped):
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

        if (
            lang.statement_terminator and lang.statement_terminator in stripped
        ) and not _is_comment_or_empty(stripped, lang):
            kept.append(line)

    kept.append(f"{lang.summary_comment_prefix} ... {len(lines)} lines total")
    return "\n".join(kept)


# ── Strategy 2: Macro definitions ───────────────────────────────────────

def summarize_macro_block(
    code: str,
    lang: LanguageConfig,
    fw: FrameworkConfig,
) -> str:
    blocks = scan_brackets(
        code,
        verbatim_string_prefix=lang.verbatim_string_prefix,
        raw_string_char=lang.raw_string_char,
    )
    if not blocks:
        return _macro_fallback(code, lang)

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

        if (
            lang.statement_terminator and lang.statement_terminator in stripped
        ) and not _is_comment_or_empty(stripped, lang):
            kept.append(line)

    kept.append(f"{lang.summary_comment_prefix} ... {len(lines)} lines total")
    return "\n".join(kept)


def _macro_fallback(code: str, lang: LanguageConfig) -> str:
    lines = code.split("\n")
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        if _is_comment_or_empty(stripped, lang):
            continue
        if lang.statement_terminator and lang.statement_terminator in stripped:
            kept.append(line)
    kept.append(f"{lang.summary_comment_prefix} ... {len(lines)} lines total")
    return "\n".join(kept)


# ── Strategy 3: Function body ───────────────────────────────────────────

def summarize_function_body(
    code: str,
    lang: LanguageConfig,
) -> str:
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

    # Build language-aware regexes from config
    scope_op_escaped = re.escape(lang.scope_operator)
    local_var_re = re.compile(
        r"^\s*"
        rf"(?:(?:{lang.local_var_modifiers})\s+)?"
        rf"([A-Za-z_]\w*(?:\s*{scope_op_escaped}\s*\w+)*(?:\s*<[^>]*>)?(?:\s*[*&]+)?)\s+"
        r"([A-Za-z_]\w*)"
        r"\s*(?:=[^;]*|)\s*;"
    )

    range_for_re = lang.range_for_re

    control_flow_res = [(regex, label) for label, regex in lang.control_flow_patterns]

    return_re = lang.return_re or re.compile(r"(?!x)x")  # never-match if None

    for line in body_lines:
        stripped = line.strip()
        if _is_comment_or_empty(stripped, lang) or stripped in ("{", "}", "{})", "};"):
            continue

        m = local_var_re.match(stripped)
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

        if range_for_re:
            rf = range_for_re.search(stripped)
            if rf:
                groups = rf.groups()
                if len(groups) >= 3:
                    desc = f"{groups[0]} {groups[1]} : {groups[2]}"
                else:
                    desc = " ".join(groups)
                summary_lines.append(_format_control_flow(lang, "for", desc))
                continue

        matched_flow = False
        for pat, kw in control_flow_res:
            m = pat.match(line)
            if m:
                cond = m.group(1).strip()
                if len(cond) > 60:
                    cond = cond[:57] + "..."
                summary_lines.append(_format_control_flow(lang, kw, cond))
                matched_flow = True
                break
        if matched_flow:
            continue

        rm = return_re.match(stripped)
        if rm:
            retval = rm.group(1).strip()
            if len(retval) > 60:
                retval = retval[:57] + "..."
            summary_lines.append(f"  return {retval}{lang.statement_terminator}")
            continue

    closing = _find_closing_brace(body_lines)
    if closing is not None:
        summary_lines.append(closing)

    body_count = len(body_lines)
    summary_lines.append(f"{lang.summary_comment_prefix} ... {body_count} lines in body")

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
