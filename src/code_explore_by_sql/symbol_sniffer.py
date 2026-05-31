"""Symbol header sniffer — heuristic block-type classification for C/C++.

Delegates to :mod:`sniffers.generic_sniffer` and accepts an optional
:class:`providers.AbstractBlockProvider`. Default provider is UnrealProvider.
"""

from __future__ import annotations

from code_explore_by_sql.block_model import BlockInfo, BracketBlock, ExtraBlock
from code_explore_by_sql.providers.base import AbstractBlockProvider
from code_explore_by_sql.sniffers.generic_sniffer import (
    sniff_block as _generic_sniff_block,
    sniff_blocks_for_file as _generic_sniff_blocks_for_file,
    sniff_semantic_blocks as _generic_sniff_semantic_blocks,
    extract_preprocessor_blocks as _generic_extract_preprocessor_blocks,
)


def sniff_block(
    preceding_lines: list[str],
    open_line_idx: int,
    all_lines: list[str],
    provider: AbstractBlockProvider | None = None,
) -> BlockInfo:
    """Classify a block by examining preceding lines (legacy API)."""
    if provider is None:
        from code_explore_by_sql.providers.unreal_provider import UnrealProvider
        provider = UnrealProvider()
    return _generic_sniff_block(
        preceding_lines, open_line_idx, all_lines,
        skip_line_re=provider.skip_line_re(),
    )


def sniff_blocks_for_file(
    lines: list[str],
    top_blocks: list[tuple[int, int]],
    provider: AbstractBlockProvider | None = None,
) -> list[tuple[int, BlockInfo]]:
    """Sniff depth=1 blocks in a file (legacy API)."""
    if provider is None:
        from code_explore_by_sql.providers.unreal_provider import UnrealProvider
        provider = UnrealProvider()
    return _generic_sniff_blocks_for_file(
        lines, top_blocks,
        skip_line_re=provider.skip_line_re(),
    )


def sniff_semantic_blocks(
    lines: list[str],
    bracket_blocks: list[BracketBlock],
    provider: AbstractBlockProvider | None = None,
    known_types: set[str] | None = None,
) -> list[tuple[int, BlockInfo]]:
    """Semantic-recursive classification of all bracket blocks.

    Returns list of (bracket_block_index, BlockInfo) for classified blocks only.
    """
    if provider is None:
        from code_explore_by_sql.providers.unreal_provider import UnrealProvider
        provider = UnrealProvider()
    return _generic_sniff_semantic_blocks(
        lines, bracket_blocks, provider, known_types,
    )


def extract_extra_blocks(
    lines: list[str],
    provider: AbstractBlockProvider | None = None,
) -> list[ExtraBlock]:
    """Extract non-brace blocks (preprocessor macros + project-specific)."""
    if provider is None:
        from code_explore_by_sql.providers.unreal_provider import UnrealProvider
        provider = UnrealProvider()
    extra = list(provider.extract_extra_blocks(lines))
    extra.extend(_generic_extract_preprocessor_blocks(lines))
    return extra
