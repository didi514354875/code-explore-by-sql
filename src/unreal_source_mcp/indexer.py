from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from .chunker import extract_chunks
from .db import (
    DEFAULT_EXCLUDE_PARTS,
    SOURCE_EXTENSIONS,
    SourceFile,
    connect,
    initialize_schema,
    replace_chunks_for_file,
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


def infer_module_name(path: Path) -> str | None:
    parts = path.parts
    if "Source" in parts:
        idx = parts.index("Source")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return None


def build_index(
    root: Path,
    db_path: Path,
    limit: int | None = None,
    extract_cached_chunks: bool = False,
) -> int:
    conn = connect(db_path)
    initialize_schema(conn)
    count = 0
    chunk_count = 0
    for path in iter_source_files(root)[:limit]:
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        digest = hashlib.sha256(content.encode("utf-8", errors="replace")).hexdigest()
        rel = str(path.relative_to(root))
        file_id = upsert_source_file(
            conn,
            SourceFile(
                file_path=rel,
                module_name=infer_module_name(path),
                raw_content=content,
                content_hash=digest,
            ),
        )
        if extract_cached_chunks:
            chunk_count += replace_chunks_for_file(conn, file_id, extract_chunks(content))
        count += 1
        if count % 500 == 0:
            conn.commit()
    conn.commit()
    conn.close()
    return chunk_count if extract_cached_chunks else count


def main() -> None:
    parser = argparse.ArgumentParser(description="Build SQLite FTS5 index for Unreal source.")
    parser.add_argument("root", type=Path, help="Unreal source root directory")
    parser.add_argument("db", type=Path, help="SQLite database path")
    parser.add_argument("--limit", type=int, default=None, help="Optional file limit for smoke tests")
    parser.add_argument(
        "--extract-chunks",
        action="store_true",
        help="Also extract and cache heuristic chunks during indexing.",
    )
    args = parser.parse_args()
    count = build_index(args.root, args.db, args.limit, extract_cached_chunks=args.extract_chunks)
    if args.extract_chunks:
        print(f"Indexed source files and cached {count} chunks into {args.db}")
    else:
        print(f"Indexed {count} files into {args.db}")


if __name__ == "__main__":
    main()
