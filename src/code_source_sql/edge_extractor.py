"""Strict edge extractor — only deterministic, unambiguous relationships.

Extracts exactly 4 edge types per plan.md:
- inheritance: class A : public B
- type_dependency: function signature types (excluding basic types)
- static_call: explicit scope calls (Super::BeginPlay, UGameplayStatics::...)
- rpc_routing: UE macro-determined implicit routing (Server -> _Implementation)

Anti-Cartesian-Product rules:
- NEVER extract generalized pointer calls (Comp->Init())
- Basic types (TArray, FString, int, FName) generate NO edges

Refactored to accept FrameworkConfig instead of hardcoded constants.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .symbol_analyzer import SymbolDef, ExtraSymbol
from .configs import FrameworkConfig

# Type pattern: UpperCamelCase that's likely a user-defined type
_TYPE_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b")

# Static call pattern: ClassName::MethodName
_STATIC_CALL_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]+)::([A-Za-z_][A-Za-z0-9_]*)\s*\(")

# Super:: call pattern
_SUPER_CALL_RE = re.compile(r"\bSuper::([A-Za-z_][A-Za-z0-9_]*)\s*\(")

# Function signature type extraction
_PARAM_TYPE_RE = re.compile(
    r"(?:const\s+)?([A-Z][A-Za-z0-9_]+)\s*(?:\*+|&)?\s+\w+"
)

# Control flow keywords to skip when scanning for static calls
_CONTROL_FLOW = frozenset({
    "if", "else", "while", "for", "switch", "catch", "return", "delete",
    "do", "goto", "break", "continue", "throw", "co_await", "co_yield", "co_return",
})


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
    language: str = "cpp",
) -> list[StrictEdge]:
    """Extract all deterministic edges for a file.

    Uses both symbol metadata and source text to find strict edges.
    """
    edges: list[StrictEdge] = []
    seen: set[tuple[str, str, str]] = set()

    all_skip = fw.skip_types | fw.noise_type_names

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
            if base not in fw.skip_types and len(base) >= 3:
                _add(qn, base, "inheritance")

        # 2. RPC routing from framework metadata
        if sym.ue_meta and fw.rpc_specifiers:
            # Skip if already an _Implementation or _Validate function
            if qn.endswith("_Implementation") or qn.endswith("_Validate"):
                continue

            for macro_name, params in sym.ue_meta.items():
                if macro_name in fw.decoration_macro_names:
                    has_rpc = False
                    for p in params:
                        if p in fw.rpc_specifiers:
                            has_rpc = True
                            break
                        if p == fw.blueprint_native_event:
                            has_rpc = True
                            break

                    if has_rpc:
                        impl_qn = f"{qn}_Implementation"
                        _add(qn, impl_qn, "rpc_routing")

                        if "WithValidation" in params:
                            validate_qn = f"{qn}_Validate"
                            _add(qn, validate_qn, "rpc_routing")

    # --- Pass 2: Source text scanning for static_call and type_dependency ---

    # Filter out symbols whose QN looks like a control flow keyword
    _CF_NAMES = frozenset({"if", "else", "while", "for", "switch", "catch", "try", "do",
                           "return", "delete", "goto", "break", "continue", "throw"})
    method_symbols = [
        s for s in symbols
        if s.block_type in ("method", "function")
        and s.qualified_name.split("::")[-1].lower() not in _CF_NAMES
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

            # 3. Static calls: ClassName::Method( or Super::Method(
            for m in _STATIC_CALL_RE.finditer(line):
                cls_name = m.group(1)
                method_name = m.group(2)
                if cls_name in ("Super",) and sym.parent_class:
                    target = f"{sym.parent_class}::{method_name}"
                    _add(qn, target, "static_call")
                elif cls_name not in all_skip and cls_name not in _CONTROL_FLOW:
                    target = f"{cls_name}::{method_name}"
                    _add(qn, target, "static_call")

            # Super:: calls
            for m in _SUPER_CALL_RE.finditer(line):
                method_name = m.group(1)
                if sym.parent_class:
                    target = f"{sym.parent_class}::{method_name}"
                    _add(qn, target, "static_call")

            # 4. Type dependencies from function signature (only on declaration lines)
            if line_idx == start:
                for m in _PARAM_TYPE_RE.finditer(line):
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
            if line in ("public:", "private:", "protected:"):
                continue
            if fw.decoration_macro_names and any(
                line.startswith(m) for m in fw.decoration_macro_names
            ):
                continue

            # Member variable: Type* Name; or Type& Name; or Type Name;
            for m in _TYPE_RE.finditer(line):
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
