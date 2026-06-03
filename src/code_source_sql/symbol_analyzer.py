"""Symbol analyzer — block classification with QN normalization and framework decoration awareness.

Implements plan.md rules:
- Black list: skip control flow, framework noise macros, basic types
- QN normalization: always ClassName::MethodName
- Framework decoration macro sniffing: look upward 1-3 lines for decoration macros
- Decoration metadata extraction for framework-specific edges
- Support for delegate_def, macro_def block types

Refactored to accept LanguageConfig + FrameworkConfig instead of hardcoded constants.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Callable

from .bracket_scanner import BracketBlock
from .configs import LanguageConfig, FrameworkConfig

# ── Shared regex constants (comment handling — language-agnostic) ───────

_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT_RE = re.compile(r"//[^\n]*")


# ── Data types ───────────────────────────────────────────────────────────

@dataclass
class SymbolDef:
    """A classified symbol from the source."""
    qualified_name: str
    block_type: str        # class, method, enum, delegate_def, macro_def, function
    file_id: int
    start_line: int        # 1-based, includes decoration macro lines above
    end_line: int          # 1-based
    decoration_meta: dict | None = None   # e.g. {"UFUNCTION": ["Server", "Reliable"]}
    parent_class: str | None = None  # for methods, the containing class name
    signature: str | None = None
    inheritance_base: str | None = None  # for class/struct, the base class name
    language: str = "cpp"  # cpp, csharp, etc.


@dataclass
class ExtraSymbol:
    """A symbol defined outside braces (framework delegates, #define macros)."""
    qualified_name: str
    block_type: str        # delegate_def, macro_def
    file_id: int
    start_line: int
    end_line: int
    signature: str = ""
    language: str = "cpp"


# ── Helpers ──────────────────────────────────────────────────────────────

def _strip_comments(text: str) -> str:
    text = _BLOCK_COMMENT_RE.sub(" ", text)
    text = _LINE_COMMENT_RE.sub(" ", text)
    return text


def _strip_template(text: str, template_re: re.Pattern) -> str:
    while True:
        new = template_re.sub(" ", text)
        if new == text:
            return text
        text = new


def _normalize_decl(text: str, lang: LanguageConfig) -> str:
    text = _strip_comments(text)
    if lang.attribute_re:
        text = lang.attribute_re.sub(" ", text)
    if lang.calling_conv_re:
        text = lang.calling_conv_re.sub(" ", text)
    if lang.export_macro_re:
        text = lang.export_macro_re.sub(" ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _extract_func_name(
    sig: str, func_name_re: re.Pattern, export_macro_re: re.Pattern,
    scope_operator: str = "::",
) -> str | None:
    sig = re.sub(rf"\s*{re.escape(scope_operator)}\s*", scope_operator, sig)
    m = func_name_re.search(sig)
    if m:
        name = m.group(1).strip()
        parts = name.split()
        parts = [p for p in parts if not export_macro_re.match(p)]
        return "::".join(p.strip() for p in " ".join(parts).split(scope_operator)) or None
    return None


def _line_before_brace(line: str) -> str:
    before, _, _ = line.partition("{")
    return before.rstrip()


def _declaration_boundary(clean: str, lang: LanguageConfig) -> bool:
    if not clean:
        return False
    if clean == "{":
        return True
    if clean.endswith(";") or clean.endswith("}") or clean.endswith("):"):
        return True
    if lang.access_spec_re.match(clean):
        return True
    return False


def _gather_declaration(
    lines: list[str],
    open_line_0: int,
    lang: LanguageConfig,
    fw: FrameworkConfig,
    max_lookback: int = 24,
) -> list[str]:
    """Gather the declaration text preceding a brace at open_line_0 (0-based)."""
    if open_line_0 < 0 or open_line_0 >= len(lines):
        return []

    context: list[str] = []
    open_text = _line_before_brace(lines[open_line_0]).strip()
    if open_text:
        context.append(open_text)

    paren_balance = open_text.count("(") - open_text.count(")")
    angle_balance = open_text.count("<") - open_text.count(">")

    if (
        open_text
        and paren_balance <= 0
        and angle_balance <= 0
        and not open_text.startswith(":")
        and not open_text.startswith(",")
        and (
            (lang.block_keyword_re and lang.block_keyword_re.search(open_text))
            or "(" in open_text
            or lang.macro_like_re.match(open_text)
        )
    ):
        return context

    for j in range(open_line_0 - 1, max(open_line_0 - max_lookback, -1), -1):
        stripped = lines[j].strip()
        if not stripped:
            if context and paren_balance <= 0 and angle_balance <= 0:
                break
            continue
        if fw.noise_macro_re and fw.noise_macro_re.match(stripped):
            continue

        # Skip preprocessor directives — they can appear inside declarations
        if stripped.startswith("#"):
            continue

        clean = _strip_comments(stripped).strip()
        if not clean:
            continue
        if _declaration_boundary(clean, lang) and paren_balance <= 0 and angle_balance <= 0:
            break

        context.insert(0, stripped)
        paren_balance += clean.count("(") - clean.count(")")
        angle_balance += clean.count("<") - clean.count(">")

        # Don't break early on constructor initializer entries (: or , lines)
        is_member_init = clean.startswith(":") or clean.startswith(",")
        if (
            not is_member_init
            and paren_balance <= 0
            and angle_balance <= 0
            and (
                (lang.block_keyword_re and lang.block_keyword_re.search(clean))
                or re.search(r"\w\s*\([^;{}]*$", clean)
                or clean.startswith("template")
            )
        ):
            break

    return context


def _sniff_decoration_above(
    lines: list[str],
    block_start_0: int,
    fw: FrameworkConfig,
) -> tuple[int, dict | None]:
    """Look 1-3 lines above block_start for framework decoration macros.

    Returns (adjusted_start_line_1based, meta_dict_or_None).
    If found, adjusts start_line upward to include the decoration macro.
    """
    if not fw.decoration_macro_re or not fw.sniff_decoration_above:
        return 0, None

    for offset in range(1, 4):
        idx = block_start_0 - offset
        if idx < 0:
            break
        stripped = lines[idx].strip()
        m = fw.decoration_macro_re.match(stripped)
        if m:
            macro_name = m.group(1)
            params_str = m.group(2)
            params = [p.strip() for p in params_str.split(",") if p.strip()]
            return idx + 1, {macro_name: params}

    return 0, None


def _classify_block(
    lines: list[str],
    block: BracketBlock,
    lang: LanguageConfig,
    fw: FrameworkConfig,
    parent_class: str | None = None,
    parent_namespace: str | None = None,
) -> tuple[str, str | None, str | None, str | None, str | None]:
    """Classify a bracket block.

    Returns (block_type, block_name, qualified_name, signature, inheritance_base).
    """
    open_0 = block.open_line - 1

    context = _gather_declaration(lines, open_0, lang, fw)
    if not context:
        return ("", None, None, None, None)

    joined = " ".join(context)
    joined_clean = _normalize_decl(joined, lang)
    if not joined_clean:
        return ("", None, None, None, None)

    classifier_sig = joined_clean
    function_sig = _strip_template(joined_clean, lang.template_re)

    # #define
    if any(lang.define_re.match(line) for line in context):
        return ("macro_def", None, None, joined_clean, None)

    # Unknown macro-like block
    if lang.macro_like_re.match(joined_clean):
        return ("", None, None, None, None)

    # extern "C"
    if lang.extern_c_re.search(joined_clean):
        return ("namespace", None, None, joined_clean, None)

    # Namespace
    if lang.namespace_sig_re:
        ns_match = lang.namespace_sig_re.match(classifier_sig)
    else:
        ns_match = None
    if ns_match:
        ns_name = ns_match.group(1)
        return ("namespace", ns_name, ns_name, joined_clean, None)

    # Enum
    m = lang.enum_re.search(classifier_sig)
    if m:
        name = m.group(1)
        qn = f"{parent_namespace}::{name}" if parent_namespace else name
        return ("enum", name, qn, joined_clean, None)

    # Class / struct
    m = lang.class_re.search(classifier_sig)
    if m:
        name = m.group(2)
        base = m.group(3) if m.lastindex >= 3 else None
        return ("class", name, name, joined_clean, base)

    # Lambda — skip (check before function detection)
    if lang.lambda_re and lang.lambda_re.search(joined_clean):
        return ("", None, None, None, None)

    # operator new/delete/etc. — skip
    if lang.operator_re and lang.operator_re.search(classifier_sig):
        return ("", None, None, None, None)

    # Strip constructor initializer list: Foo(params) : member(val), ... -> Foo(params)
    if lang.init_list_re:
        init_match = lang.init_list_re.search(function_sig)
        if init_match:
            function_sig = function_sig[:init_match.start() + 1]
        init_match2 = lang.init_list_re.search(classifier_sig)
        if init_match2:
            classifier_sig = classifier_sig[:init_match2.start() + 1]

    # Function / method detection
    test_sig = lang.trailing_mods_re.sub("", function_sig).rstrip()
    test_sig = re.sub(r"\s+", " ", test_sig).strip()
    if test_sig.endswith(")") or re.search(r"\)\s*(?:const\s*)?$", test_sig):
        # Destructor
        dtor = lang.dtor_re.search(test_sig)
        if dtor:
            raw_name = dtor.group(1)
            qn = f"{parent_class}::{raw_name}" if parent_class else raw_name
            block_type = "method" if parent_class else "function"
            return (block_type, raw_name, qn, joined_clean, None)

        # Control flow — skip
        if lang.control_flow_re.match(test_sig):
            return ("", None, None, None, None)
        if lang.macro_like_re.match(test_sig):
            return ("", None, None, None, None)

        raw_name = _extract_func_name(
            test_sig, lang.func_name_re, lang.export_macro_re,
            scope_operator=lang.scope_operator,
        )
        if raw_name:
            func_part = raw_name.split("::")[-1]
            if func_part in lang.control_flow_names:
                return ("", None, None, None, None)
            if "::" in raw_name:
                qn = raw_name
            else:
                qn = f"{parent_class}::{raw_name}" if parent_class else raw_name
            block_type = "method" if parent_class else "function"
            return (block_type, raw_name, qn, joined_clean, None)

    return ("", None, None, None, None)


# ── Main analysis ────────────────────────────────────────────────────────

def analyze_file(
    lines: list[str],
    file_id: int,
    lang: LanguageConfig,
    fw: FrameworkConfig,
) -> tuple[list[SymbolDef], list[ExtraSymbol]]:
    """Analyze a file and extract all symbols with QN normalization.

    Returns (bracket_symbols, extra_symbols).
    """
    content = "\n".join(lines)
    from .bracket_scanner import scan_brackets, compute_parent_map

    blocks = scan_brackets(
        content,
        verbatim_string_prefix=lang.verbatim_string_prefix,
        raw_string_char=lang.raw_string_char,
    )
    if not blocks:
        return [], extract_extra_symbols(lines, file_id, lang, fw)

    parent_map = compute_parent_map(blocks)

    # Build block index for parent lookup
    block_by_key: dict[tuple[int, int], int] = {}
    for i, b in enumerate(blocks):
        block_by_key[(b.open_line, b.depth)] = i

    # Track class name at each depth for QN assembly
    class_at_depth: dict[int, str] = {}
    namespace_at_depth: dict[int, str] = {}

    symbols: list[SymbolDef] = []

    # Sort blocks by open_line so parents are always processed before children
    sorted_indices = sorted(range(len(blocks)), key=lambda i: blocks[i].open_line)

    for i in sorted_indices:
        block = blocks[i]
        key = (block.open_line, block.depth)
        parent_key = parent_map.get(key)

        # Determine parent class and namespace
        parent_class: str | None = None
        parent_namespace: str | None = None
        if parent_key is not None:
            parent_idx = block_by_key.get(parent_key)
            if parent_idx is not None:
                parent_class = class_at_depth.get(parent_idx)
                parent_namespace = namespace_at_depth.get(parent_idx)

        btype, bname, qn, sig, base = _classify_block(
            lines, block, lang, fw, parent_class, parent_namespace
        )
        if not btype or not bname:
            continue

        # Framework decoration sniffing — look above the block
        deco_start_line, deco_meta = _sniff_decoration_above(lines, block.open_line - 1, fw)
        actual_start = deco_start_line if deco_start_line > 0 else block.open_line

        if btype == "class":
            class_at_depth[i] = bname
        if btype == "namespace" and bname:
            ns_qn = bname
            if parent_namespace:
                ns_qn = f"{parent_namespace}::{bname}"
            namespace_at_depth[i] = ns_qn

        if btype in ("function",) and parent_class:
            btype = "method"

        symbols.append(SymbolDef(
            qualified_name=qn or bname,
            block_type=btype,
            file_id=file_id,
            start_line=actual_start,
            end_line=block.close_line,
            decoration_meta=deco_meta,
            parent_class=parent_class,
            signature=sig,
            inheritance_base=base,
            language=lang.name,
        ))

    extra = extract_extra_symbols(lines, file_id, lang, fw)
    return symbols, extra


def extract_extra_symbols(
    lines: list[str],
    file_id: int,
    lang: LanguageConfig,
    fw: FrameworkConfig,
) -> list[ExtraSymbol]:
    """Extract non-brace symbols: framework-specific delegates and #define macros."""
    results: list[ExtraSymbol] = []

    for i, line in enumerate(lines, start=1):
        stripped = line.strip()

        # Framework declaration macros (e.g., DECLARE_DELEGATE)
        if fw.declare_macro_re and fw.parse_delegate_name:
            m = fw.declare_macro_re.match(stripped)
            if m and "delegate_def" in fw.extra_symbol_types:
                delegate_name = fw.parse_delegate_name(stripped)
                if delegate_name:
                    results.append(ExtraSymbol(
                        qualified_name=delegate_name,
                        block_type="delegate_def",
                        file_id=file_id,
                        start_line=i,
                        end_line=i,
                        signature=stripped,
                        language=lang.name,
                    ))
                continue

        # #define macros (C/C++ only)
        if "macro_def" in fw.extra_symbol_types and lang.define_re:
            dm = re.match(r"#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)", stripped)
            if dm:
                name = dm.group(1)
                if fw.macro_name_filter and fw.macro_name_filter(name):
                    continue
                results.append(ExtraSymbol(
                    qualified_name=name,
                    block_type="macro_def",
                    file_id=file_id,
                    start_line=i,
                    end_line=i,
                    signature=stripped,
                    language=lang.name,
                ))

    return results
