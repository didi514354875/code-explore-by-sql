"""Unreal Engine provider — extends C/C++ with UE macro handling."""

from __future__ import annotations

import re
from .base import IncludeDirective
from .cc_provider import CCProvider, CC_NOISE_WORDS
from code_explore_by_sql.block_model import ExtraBlock

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

_UE_MACRO_RE = re.compile(
    r"^\s*(" + "|".join(re.escape(m) for m in UE_SKIP_MACROS) + r")\s*\("
)

# UE decoration macros with their parameters: UCLASS(...), UPROPERTY(...), etc.
_UE_DECORATION_RE = re.compile(
    r"^\s*(UCLASS|USTRUCT|UENUM|UFUNCTION|UPROPERTY|UINTERFACE)"
    r"\s*\(([^)]*)\)"
)

# UE declaration macros: DECLARE_DELEGATE, DECLARE_DYNAMIC_MULTICAST_DELEGATE_SixParams, etc.
_UE_DECLARE_RE = re.compile(
    r"^\s*(DECLARE_\w+(?:_\w+)*)\s*\("
)


class UnrealProvider(CCProvider):
    """Unreal Engine C++ provider — UE macro filtering and extraction."""

    @property
    def name(self) -> str:
        return "unreal"

    def filter_lines(self, lines: list[str]) -> list[str]:
        """Return lines that match UE macro patterns (to be skipped)."""
        return [ln for ln in lines if _UE_MACRO_RE.match(ln.strip())]

    def skip_line_re(self) -> re.Pattern | None:
        """Return the UE macro regex for use by symbol_sniffer."""
        return _UE_MACRO_RE

    def classify_macro(self, line: str) -> tuple[str, str] | None:
        """Classify a UE decoration macro line. Returns (macro_type, params_text)."""
        m = _UE_DECORATION_RE.match(line)
        if m:
            return (m.group(1), m.group(2))
        return None

    def extract_extra_blocks(self, lines: list[str]) -> list[ExtraBlock]:
        """Extract UE decoration and declaration macros as non-brace blocks."""
        blocks: list[ExtraBlock] = []
        for i, line in enumerate(lines, start=1):
            stripped = line.strip()

            # UE decoration macros: UCLASS(...), UPROPERTY(...), etc.
            m = _UE_DECORATION_RE.match(stripped)
            if m:
                blocks.append(ExtraBlock(
                    name=m.group(1),
                    block_type="ue_macro",
                    start_line=i,
                    end_line=i,
                    params=m.group(2),
                    signature=stripped,
                ))
                continue

            # UE declaration macros: DECLARE_DELEGATE(...), etc.
            m = _UE_DECLARE_RE.match(stripped)
            if m:
                blocks.append(ExtraBlock(
                    name=m.group(1),
                    block_type="ue_declare",
                    start_line=i,
                    end_line=i,
                    params=None,
                    signature=stripped,
                ))
                continue

        return blocks

    # UE-specific noise in addition to the C/C++ base set
    _UE_EXTRA_NOISE: frozenset[str] = frozenset({
        'Pin', 'Section', 'View', 'Instance', 'Platform',
        'This', 'Material', 'Class', 'Struct', 'Widget', 'Level',
        'Normal', 'Width', 'Label', 'Desc', 'Stats', 'Default',
        'Inc', 'System', 'Interface', 'Entry', 'Actor',
    })

    def skip_symbol_names(self) -> frozenset[str]:
        return CC_NOISE_WORDS | self._UE_EXTRA_NOISE
