"""Strict edge extractor — only deterministic, unambiguous relationships.

Extracts exactly 4 edge types per plan.md:
- inheritance: class A : public B
- type_dependency: function signature types (excluding basic types)
- static_call: explicit scope calls (Super::BeginPlay, UGameplayStatics::...)
- rpc_routing: framework-determined implicit routing (Server -> _Implementation)

Anti-Cartesian-Product rules:
- NEVER extract generalized pointer calls (Comp->Init())
- Basic types (TArray, FString, int, FName) generate NO edges

Refactored to accept LanguageConfig + FrameworkConfig instead of hardcoded constants.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .symbol_analyzer import SymbolDef, ExtraSymbol
from .configs import FrameworkConfig, LanguageConfig


@dataclass
class StrictEdge:
    source_qn: str
    target_qn: str
    edge_type: str  # inheritance, type_dependency, static_call, rpc_routing
    language: str = "cpp"


def extract_edges(
    symbols: list[SymbolDef],
    extra_symbols: list[ExtraSymbol],
    lines: list[str],
    fw: FrameworkConfig,
    lang: LanguageConfig,
) -> list[StrictEdge]:
    """Extract all deterministic edges for a file.

    Uses both symbol metadata and source text to find strict edges.
    All regex patterns come from LanguageConfig and FrameworkConfig.
    """
    language = lang.name
    scope_op = lang.scope_operator
    base_kw = lang.base_keyword
    type_re = lang.type_re
    static_call_re = lang.static_call_re
    super_call_re = lang.super_call_re
    param_type_re = lang.param_type_re
    control_flow_names = lang.control_flow_names
    access_spec_names = lang.access_spec_names

    edges: list[StrictEdge] = []
    seen: set[tuple[str, str, str]] = set()

    all_skip = lang.basic_skip_types | fw.skip_types | fw.noise_type_names

    def _add(src: str, tgt: str, etype: str) -> None:
        if src == tgt:
            return
        key = (src, tgt, etype)
        if key not in seen:
            seen.add(key)
            edges.append(StrictEdge(source_qn=src, target_qn=tgt, edge_type=etype, language=language))

    # Build a lookup of QN -> SymbolDef for resolving static calls
    qn_set: set[str] = set()
    for s in symbols:
        qn_set.add(s.qualified_name)

    # --- Pass 1: Symbol metadata edges ---

    for sym in symbols:
        qn = sym.qualified_name

        # 1. Inheritance
        if sym.block_type == "class" and sym.inheritance_base:
            base = sym.inheritance_base
            if base not in all_skip and len(base) >= 3:
                _add(qn, base, "inheritance")

        # 2. Framework-specific edges from decoration metadata
        if sym.decoration_meta and fw.extract_framework_edges:
            for target_qn, edge_type in fw.extract_framework_edges(qn, sym.decoration_meta):
                _add(qn, target_qn, edge_type)

    # --- Pass 2: Source text scanning for static_call and type_dependency ---

    # QN internal convention uses "::" as separator regardless of language.
    # scope_operator is only used for source text regex matching above.
    _QN_SEP = "::"

    method_symbols = [
        s for s in symbols
        if s.block_type in ("method", "function")
        and s.qualified_name.split(_QN_SEP)[-1].lower() not in control_flow_names
    ]

    for sym in method_symbols:
        qn = sym.qualified_name
        start = sym.start_line - 1
        end = sym.end_line

        for line_idx in range(start, min(end, len(lines))):
            line = lines[line_idx].strip()

            # Skip comments and preprocessor
            if line.startswith("//") or line.startswith("/*") or line.startswith("#"):
                continue
            # Skip framework decoration macro lines
            if fw.decoration_macro_names and any(
                line.startswith(m) for m in fw.decoration_macro_names
            ):
                continue
            # Skip string literals (rough check)
            if line.startswith('"') or line.startswith('R"'):
                continue

            # 3. Static calls: ClassName.Method( or ClassName::Method(
            if static_call_re:
                for m in static_call_re.finditer(line):
                    cls_name = m.group(1)
                    method_name = m.group(2)
                    if cls_name == base_kw and sym.parent_class:
                        target = f"{sym.parent_class}::{method_name}"
                        _add(qn, target, "static_call")
                    elif cls_name not in all_skip and cls_name not in control_flow_names:
                        target = f"{cls_name}::{method_name}"
                        _add(qn, target, "static_call")

            # Super/base calls
            if super_call_re:
                for m in super_call_re.finditer(line):
                    method_name = m.group(1)
                    if sym.parent_class:
                        target = f"{sym.parent_class}::{method_name}"
                        _add(qn, target, "static_call")

            # 4. Type dependencies from function signature (only on declaration lines)
            if line_idx == start and param_type_re:
                for m in param_type_re.finditer(line):
                    tname = m.group(1)
                    if tname not in all_skip and len(tname) >= 3:
                        _add(qn, tname, "type_dependency")

    # --- Pass 3: Type dependencies from class member variables ---
    class_symbols = [s for s in symbols if s.block_type == "class"]
    for sym in class_symbols:
        qn = sym.qualified_name
        start = sym.start_line - 1
        end = sym.end_line

        for line_idx in range(start, min(end, len(lines))):
            line = lines[line_idx].strip()
            if not line:
                continue
            if line.startswith("//") or line.startswith("/*") or line.startswith("#"):
                continue
            if line in access_spec_names:
                continue
            if fw.decoration_macro_names and any(
                line.startswith(m) for m in fw.decoration_macro_names
            ):
                continue

            # Member variable: Type* Name; or Type& Name; or Type Name;
            if type_re:
                for m in type_re.finditer(line):
                    tname = m.group(1)
                    if tname in all_skip:
                        continue
                    if len(tname) < 3:
                        continue
                    pos = m.end()
                    rest = line[pos:].lstrip() if pos < len(line) else ""
                    if rest and (rest[0] in "*&" or (rest[0].isalpha() or rest[0] == "_")):
                        _add(qn, tname, "type_dependency")

    return edges
