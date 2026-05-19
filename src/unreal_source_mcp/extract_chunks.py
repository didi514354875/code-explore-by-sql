from __future__ import annotations

import argparse
from pathlib import Path

from .chunker import extract_chunks
from .db import connect, initialize_schema, replace_chunks_for_file


def cache_chunks(db_path: Path, limit_files: int | None = None) -> int:
    conn = connect(db_path)
    initialize_schema(conn)
    total = 0
    rows = conn.execute("SELECT id, raw_content FROM source_files ORDER BY id").fetchall()
    for row in rows[:limit_files]:
        total += replace_chunks_for_file(conn, row["id"], extract_chunks(row["raw_content"]))
        conn.commit()
    conn.close()
    return total


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract and cache heuristic chunks from indexed files.")
    parser.add_argument("db", type=Path)
    parser.add_argument("--limit-files", type=int, default=None)
    args = parser.parse_args()
    total = cache_chunks(args.db, args.limit_files)
    print(f"Cached {total} chunks")


if __name__ == "__main__":
    main()
