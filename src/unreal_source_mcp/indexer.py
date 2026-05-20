from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from .db import (
    DEFAULT_EXCLUDE_PARTS,
    SOURCE_EXTENSIONS,
    SourceFile,
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


def infer_module_name(path: Path) -> str | None:
    parts = path.parts
    if "Source" in parts:
        idx = parts.index("Source")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return None


def build_index(root: Path, db_path: Path, limit: int | None = None) -> int:
    conn = connect(db_path)
    initialize_schema(conn)
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
                module_name=infer_module_name(path),
                raw_content=content,
                content_hash=digest,
            ),
        )
        count += 1
        if count % 500 == 0:
            conn.commit()
    conn.commit()
    conn.close()
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Build SQLite FTS5 index for Unreal source.")
    parser.add_argument("root", type=Path, help="Unreal source root directory")
    parser.add_argument("db", type=Path, help="SQLite database path")
    parser.add_argument("--limit", type=int, default=None, help="Optional file limit for smoke tests")
    args = parser.parse_args()
    count = build_index(args.root, args.db, args.limit)
    print(f"Indexed {count} files into {args.db}")


if __name__ == "__main__":
    main()
