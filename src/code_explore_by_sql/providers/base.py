"""Abstract provider interface for language-specific block sniffing and include parsing."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from code_explore_by_sql.block_model import ExtraBlock


@dataclass(frozen=True)
class IncludeDirective:
    path: str
    line_number: int
    directive_type: str = "include"  # "include", "import", "using", etc.


class AbstractBlockProvider(ABC):
    """Protocol for language/project-specific block classification and directive parsing.

    A provider controls:
    1. Which lines to **skip** during block sniffing (e.g. UE macros).
    2. How to **parse include/import directives** for dependency edges.
    3. How to **extract non-brace blocks** (project-specific macros, declarations).
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Short identifier, e.g. 'cc', 'unreal', 'csharp'."""
        ...

    @property
    @abstractmethod
    def source_extensions(self) -> set[str]:
        """File extensions this provider handles, e.g. {'.cpp', '.h'}."""
        ...

    @abstractmethod
    def filter_lines(self, lines: list[str]) -> list[str]:
        """Return lines that should be **ignored** when sniffing block types.

        For standard C/C++ this returns an empty list.
        For Unreal, this filters out UCLASS(), UPROPERTY(), etc.
        """
        ...

    @abstractmethod
    def parse_include_directives(self, lines: list[str]) -> list[IncludeDirective]:
        """Parse preprocessor/directive lines into IncludeDirective objects."""
        ...

    def skip_line_re(self):
        """Return compiled regex for lines to skip during sniffing, or None."""
        return None

    def extract_extra_blocks(self, lines: list[str]) -> list[ExtraBlock]:
        """Extract project-specific blocks that don't use braces.

        Override in project-specific providers (e.g., UnrealProvider).
        Default returns empty list.
        """
        return []

    def classify_macro(self, line: str) -> tuple[str, str] | None:
        """Classify a macro line. Returns (macro_type, params_text) or None."""
        return None

    def skip_symbol_names(self) -> frozenset[str]:
        """Return symbol names that should be filtered during reference tracking.

        These are overly generic names (e.g. "set", "value", "name") that appear
        in nearly every file as identifiers but carry no structural meaning.
        For these, only structural references (calls, member access, templates)
        are kept; bare identifier occurrences are dropped.
        """
        return frozenset()
