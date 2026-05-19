from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path
from typing import Any

from .chunker import extract_chunks
from .db import (
    connect,
    get_cached_chunks,
    get_source_by_path,
    initialize_schema,
    replace_chunks_for_file,
    search_chunks,
    search_source,
)


def estimate_tokens(text: str) -> int:
    """Approximate token count without model-specific tokenization."""
    return math.ceil(len(text) / 4) if text else 0


def payload_chars(value: Any) -> int:
    return len(json.dumps(value, ensure_ascii=False))


def simulate_search_then_extract(
    conn: Any,
    query: str,
    module: str | None,
    symbol: str | None,
    limit_files: int,
    chunks_per_file: int,
) -> list[dict[str, Any]]:
    files = search_source(conn, query=query, module=module, limit=limit_files)
    results: list[dict[str, Any]] = []
    for file_row in files:
        source = get_source_by_path(conn, file_row["file_path"])
        if source is None:
            continue
        chunks = get_cached_chunks(conn, source["id"], symbol=symbol, limit=chunks_per_file)
        if not chunks:
            extracted = extract_chunks(source["raw_content"])
            replace_chunks_for_file(conn, source["id"], extracted)
            conn.commit()
            chunks = get_cached_chunks(conn, source["id"], symbol=symbol, limit=chunks_per_file)
        for chunk in chunks[:chunks_per_file]:
            chunk["file_path"] = source["file_path"]
            chunk["module_name"] = source["module_name"]
            chunk["file_rank"] = file_row["rank"]
            results.append(chunk)
    return results


def benchmark_query(
    conn: Any,
    query: str,
    module: str | None = None,
    symbol: str | None = None,
    limit: int = 5,
    body_chars: int = 4000,
    chunks_per_file: int = 3,
) -> dict[str, Any]:
    started = time.perf_counter()
    file_hits = search_source(conn, query=query, module=module, limit=limit)
    file_search_ms = (time.perf_counter() - started) * 1000

    top_file_path: str | None = None
    full_file_chars = 0
    full_file_tokens = 0
    full_file_lines = 0

    if file_hits:
        top_file = get_source_by_path(conn, file_hits[0]["file_path"])
        if top_file is not None:
            top_file_path = top_file["file_path"]
            full_content = top_file["raw_content"]
            full_file_chars = len(full_content)
            full_file_tokens = estimate_tokens(full_content)
            full_file_lines = len(full_content.splitlines())

    started = time.perf_counter()
    chunk_hits = search_chunks(
        conn,
        query=query,
        module=module,
        limit=limit,
        body_chars=body_chars,
    )
    chunk_search_ms = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    combined_hits = simulate_search_then_extract(
        conn,
        query=query,
        module=module,
        symbol=symbol,
        limit_files=limit,
        chunks_per_file=chunks_per_file,
    )
    combined_search_ms = (time.perf_counter() - started) * 1000

    chunk_chars = sum(len(hit.get("body") or "") for hit in chunk_hits)
    combined_chars = sum(len(hit.get("body") or "") for hit in combined_hits)

    return {
        "query": query,
        "module": module,
        "symbol": symbol,
        "top_file_path": top_file_path,
        "file_search_ms": round(file_search_ms, 3),
        "chunk_search_ms": round(chunk_search_ms, 3),
        "combined_search_ms": round(combined_search_ms, 3),
        "file_hits": len(file_hits),
        "chunk_hits": len(chunk_hits),
        "combined_hits": len(combined_hits),
        "file_search_payload_chars": payload_chars(file_hits),
        "chunk_search_payload_chars": payload_chars(chunk_hits),
        "combined_search_payload_chars": payload_chars(combined_hits),
        "full_file_chars": full_file_chars,
        "full_file_lines": full_file_lines,
        "full_file_estimated_tokens": full_file_tokens,
        "chunk_body_chars": chunk_chars,
        "chunk_body_estimated_tokens": estimate_tokens("x" * chunk_chars),
        "combined_body_chars": combined_chars,
        "combined_body_estimated_tokens": estimate_tokens("x" * combined_chars),
        "chunk_cache_hit": bool(chunk_hits),
    }


def summarize_reports(reports: list[dict[str, Any]]) -> dict[str, Any]:
    if not reports:
        return {"queries": 0}

    def avg(key: str) -> float:
        return round(sum(float(report[key]) for report in reports) / len(reports), 3)

    file_tokens = sum(int(report["full_file_estimated_tokens"]) for report in reports)
    chunk_tokens = sum(int(report["chunk_body_estimated_tokens"]) for report in reports)
    combined_tokens = sum(int(report["combined_body_estimated_tokens"]) for report in reports)

    return {
        "queries": len(reports),
        "avg_file_search_ms": avg("file_search_ms"),
        "avg_chunk_search_ms": avg("chunk_search_ms"),
        "avg_combined_search_ms": avg("combined_search_ms"),
        "avg_file_search_payload_chars": avg("file_search_payload_chars"),
        "avg_chunk_search_payload_chars": avg("chunk_search_payload_chars"),
        "avg_combined_search_payload_chars": avg("combined_search_payload_chars"),
        "file_to_chunk_token_ratio": round(file_tokens / chunk_tokens, 3) if chunk_tokens else None,
        "file_to_combined_token_ratio": round(file_tokens / combined_tokens, 3) if combined_tokens else None,
        "chunk_cache_hit_rate": round(
            sum(1 for report in reports if report["chunk_cache_hit"]) / len(reports), 3
        ),
    }


def load_queries(query_args: list[str], queries_file: Path | None) -> list[dict[str, Any]]:
    queries: list[dict[str, Any]] = []
    for query in query_args:
        queries.append({"query": query})
    if queries_file is not None:
        loaded = json.loads(queries_file.read_text(encoding="utf-8"))
        if not isinstance(loaded, list):
            raise ValueError("queries file must contain a JSON array")
        for item in loaded:
            if not isinstance(item, dict) or "query" not in item:
                raise ValueError("each query entry must be an object containing a 'query' field")
            queries.append(item)
    return queries


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark file search vs chunk search to estimate latency and token savings."
    )
    parser.add_argument("db", type=Path, help="SQLite database path")
    parser.add_argument("--query", action="append", default=[], help="Benchmark a query string")
    parser.add_argument("--queries-file", type=Path, default=None, help="JSON file with query objects")
    parser.add_argument("--module", default=None, help="Optional module filter applied to CLI queries")
    parser.add_argument("--symbol", default=None, help="Optional symbol filter for combined extraction")
    parser.add_argument("--limit", type=int, default=5, help="Max files/chunks per query")
    parser.add_argument("--chunks-per-file", type=int, default=3, help="Combined retrieval chunks per file")
    parser.add_argument("--body-chars", type=int, default=4000, help="Max chars returned per chunk hit")
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty print JSON output for easier inspection",
    )
    args = parser.parse_args()

    queries = load_queries(args.query, args.queries_file)
    if not queries:
        parser.error("provide at least one --query or a --queries-file")

    conn = connect(args.db)
    initialize_schema(conn)
    reports = []
    for item in queries:
        reports.append(
            benchmark_query(
                conn,
                query=item["query"],
                module=item.get("module", args.module),
                symbol=item.get("symbol", args.symbol),
                limit=item.get("limit", args.limit),
                body_chars=item.get("body_chars", args.body_chars),
                chunks_per_file=item.get("chunks_per_file", args.chunks_per_file),
            )
        )
    output = {"summary": summarize_reports(reports), "reports": reports}
    print(json.dumps(output, indent=2 if args.pretty else None, ensure_ascii=False))


if __name__ == "__main__":
    main()
