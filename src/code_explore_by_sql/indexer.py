from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from .db import (
    DEFAULT_EXCLUDE_PARTS,
    SOURCE_EXTENSIONS,
    SourceFile,
    backfill_structural_index,
    connect,
    initialize_schema,
    upsert_source_file,
)


def iter_source_files(root: Path, include_plugins: bool = True) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in SOURCE_EXTENSIONS:
            continue
        parts = set(path.parts)
        excludes = DEFAULT_EXCLUDE_PARTS if include_plugins else DEFAULT_EXCLUDE_PARTS | {"Plugins"}
        if parts & excludes:
            continue
        files.append(path)
    return files


_INVALID_MODULE_NAMES = frozenset({
    "Private", "Public", "Classes", "Inc", "Src", "Source",
    "Include", "Internal", "Tests", "Test",
})


def infer_module_name(
    path: Path,
    source_marker: str = "Source",
    categories: set[str] | None = None,
) -> str | None:
    """Infer the module name from the file path.

    Looks for `source_marker` in the path, then takes the next component.
    Skips components that are in `categories` or `_INVALID_MODULE_NAMES`.

    Examples with source_marker="Source", categories={"Runtime","Editor"}:
      .../Source/Runtime/Renderer/Private/... -> "Renderer"
      .../Source/MyModule/Private/...          -> "MyModule"

    With default categories=None (no skipping):
      .../Source/Runtime/Renderer/Private/... -> "Runtime"
      .../src/core/...                         -> None (no "Source" marker)
    """
    parts = path.parts
    if source_marker not in parts:
        return None

    idx = parts.index(source_marker)
    cats = categories or set()

    # Try successive path components after source_marker
    # Stop before the last component (the filename itself)
    max_offset = len(parts) - idx - 1
    for offset in range(1, max_offset):
        candidate = parts[idx + offset]
        if candidate in _INVALID_MODULE_NAMES:
            continue
        if candidate in cats:
            continue
        return candidate

    return None


def build_index(
    root: Path,
    db_path: Path,
    limit: int | None = None,
    source_marker: str = "Source",
    categories: set[str] | None = None,
    provider_name: str = "unreal",
) -> int:
    """Two-phase build: fast file import, then parallel structural indexing.

    provider_name: name of the provider to use for include parsing and line filtering.
                   "unreal" (default) for UE projects, "cc" for standard C/C++.
    """
    import time

    conn = connect(db_path)
    initialize_schema(conn)

    # Phase 1: Import file contents (skip structural indexing for speed)
    print(f"Phase 1: Importing files...", flush=True)
    start = time.time()
    count = 0
    for path in iter_source_files(root)[:limit]:
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        digest = hashlib.sha256(content.encode("utf-8", errors="replace")).hexdigest()
        rel = str(path.relative_to(root))
        upsert_source_file(
            conn,
            SourceFile(
                file_path=rel,
                module_name=infer_module_name(path, source_marker, categories),
                raw_content=content,
                content_hash=digest,
            ),
            skip_structural=True,
        )
        count += 1
        if count % 500 == 0:
            conn.commit()
    conn.commit()
    elapsed = time.time() - start
    print(f"Phase 1 done: {count} files in {elapsed:.1f}s", flush=True)

    # Phase 2: Parallel structural indexing
    print(f"Phase 2: Building structural index (provider={provider_name})...", flush=True)
    start = time.time()
    backfill_structural_index(conn, batch_size=500, workers=0, provider_name=provider_name)
    elapsed = time.time() - start
    print(f"Phase 2 done in {elapsed:.1f}s", flush=True)

    conn.close()
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Build SQLite FTS5 index for source code.")
    parser.add_argument("root", type=Path, help="Source root directory")
    parser.add_argument("db", type=Path, help="SQLite database path")
    parser.add_argument("--limit", type=int, default=None, help="Optional file limit for smoke tests")
    parser.add_argument(
        "--source-marker",
        default="Source",
        help="Path component marking the source root (default: Source). "
        'Use "src" for typical CMake projects, "." to use the root.',
    )
    parser.add_argument(
        "--categories",
        default="",
        help="Comma-separated category directories to skip after source marker "
        '(e.g. "Runtime,Editor,Developer"). Empty = no skipping.',
    )
    parser.add_argument(
        "--provider",
        default="unreal",
        choices=["unreal", "cc"],
        help="Provider for include parsing and line filtering (default: unreal). "
        'Use "cc" for standard C/C++ projects without UE macros.',
    )
    args = parser.parse_args()

    cats = {c.strip() for c in args.categories.split(",") if c.strip()} or None
    count = build_index(args.root, args.db, args.limit, args.source_marker, cats, args.provider)
    print(f"Indexed {count} files into {args.db}")


if __name__ == "__main__":
    main()
