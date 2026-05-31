"""Shared data models for bracket scanning and symbol sniffing."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class BracketBlock:
    open_line: int
    close_line: int
    depth: int
    is_complete: bool


@dataclass(frozen=True)
class BlockInfo:
    """Classification result for a bracket-delimited block.

    block_type is one of: namespace, class, struct, enum, function, method, macro_def.
    Unclassifiable blocks are represented as None (not stored).
    """
    block_type: str
    block_name: str | None
    signature: str | None
    params: str | None = None
    extra_fields: dict | None = None


@dataclass(frozen=True)
class ExtraBlock:
    """A symbol-defining construct outside the brace hierarchy.

    Covers preprocessor macros, UE decoration/declaration macros,
    and any project-specific construct that doesn't use { }.
    """
    name: str
    block_type: str       # 'ue_macro', 'ue_declare', 'macro_def'
    start_line: int       # 1-based
    end_line: int
    params: str | None = None
    signature: str = ""
