"""Standard C/C++ provider — no project-specific macro filtering."""

from __future__ import annotations

import re
from .base import AbstractBlockProvider, IncludeDirective

_INCLUDE_RE = re.compile(r'#\s*include\s+[<"]([^>"]+)[>"]')

CC_SOURCE_EXTENSIONS = {".h", ".hpp", ".hh", ".inl", ".cpp", ".cc", ".cxx"}

# Generic words that appear as identifiers everywhere but carry no
# structural meaning.  For these, only structural references
# (calls, member access, template usage) are kept.
CC_NOISE_WORDS: frozenset[str] = frozenset({
    'set', 'get', 'value', 'name', 'type', 'not', 'check', 'first',
    'from', 'empty', 'count', 'read', 'write', 'all', 'none',
    'input', 'output', 'error', 'warning', 'info', 'index',
    'size', 'data', 'result', 'status', 'begin', 'end',
})


class CCProvider(AbstractBlockProvider):
    """Standard C/C++ provider with #include parsing and no macro filtering."""

    @property
    def name(self) -> str:
        return "cc"

    @property
    def source_extensions(self) -> set[str]:
        return set(CC_SOURCE_EXTENSIONS)

    def filter_lines(self, lines: list[str]) -> list[str]:
        """Standard C/C++ has no lines to skip during sniffing."""
        return []

    def parse_include_directives(self, lines: list[str]) -> list[IncludeDirective]:
        directives: list[IncludeDirective] = []
        for i, line in enumerate(lines, start=1):
            stripped = line.lstrip()
            if not stripped.startswith("#include"):
                continue
            m = _INCLUDE_RE.match(stripped)
            if m:
                directives.append(IncludeDirective(m.group(1), i, "include"))
        return directives

    def skip_line_re(self) -> re.Pattern | None:
        """Return None — standard C/C++ skips nothing."""
        return None

    def skip_symbol_names(self) -> frozenset[str]:
        return CC_NOISE_WORDS
