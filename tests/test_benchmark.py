"""Query efficiency and token consumption benchmark.

Compares different query approaches:
  A) Direct FTS5 search (simple keyword)
  B) Full pipeline (FTS5 + history + scoring)
  C) Clustered search
  D) Scope-filtered search
  E) find_callers
  F) find_include_graph
  G) get_file_content (anchor vs full vs line-range)
  H) Skill-driven multi-step workflow

Usage:
    PYTHONPATH=src python3 -u tests/test_benchmark.py
"""

from __future__ import annotations

import json
import sqlite3
import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from code_explore_by_sql.db import (
    connect,
    initialize_schema,
    search_source,
    search_source_with_feedback,
    _search_fts,
    _fts5_escape,
    _get_history_signals,
    _extract_search_terms,
    load_bracket_index,
    find_enclosing_block,
    get_source_by_path,
    get_source_anchored,
)

DB_PATH = os.environ.get("UNREAL_SOURCE_DB", "unreal.db")

def sizeof_fmt(n):
    if n < 1024:
        return f"{n} B"
    elif n < 1024 * 1024:
        return f"{n/1024:.1f} KB"
    else:
        return f"{n/(1024*1024):.1f} MB"


def estimate_tokens(text: str) -> int:
    """Rough estimate: ~4 chars per token for code."""
    return len(text) // 4


def measure(fn, *args, **kwargs):
    t0 = time.perf_counter()
    result = fn(*args, **kwargs)
    elapsed = time.perf_counter() - t0
    # Estimate response size
    resp_text = json.dumps(result, default=str)
    resp_bytes = len(resp_text.encode("utf-8"))
    return result, elapsed, resp_bytes


conn = connect(DB_PATH)
initialize_schema(conn)

print("=" * 80)
print("QUERY EFFICIENCY & TOKEN CONSUMPTION BENCHMARK")
print("=" * 80)
print(f"Database: 84,696 files, 2.49M brackets, 509K include edges")
print(f"Token estimate: ~4 chars/token (code)")
print()

results = []

# =========================================================================
# A) Direct FTS5 search — different term frequencies
# =========================================================================
print("─" * 80)
print("A) DIRECT FTS5 SEARCH (search_source)")
print("─" * 80)

queries = [
    ("Render", "high-freq, 11K matches"),
    ("GetGBuffer", "medium-freq, ~1K matches"),
    ("FLumenSurfaceCacheData", "rare, ~10 matches"),
    ("FSceneView", "medium-freq"),
    ("IMPLEMENT_MODULE", "high-freq macro"),
    ("Nanite", "medium-freq"),
]

for query, desc in queries:
    r, t, sz = measure(search_source, conn, query, limit=20)
    tokens = estimate_tokens(json.dumps(r, default=str))
    results.append(("A_search", query, t, sz, tokens, len(r), desc))
    print(f"  {query:30s} {t*1000:8.0f}ms  {sizeof_fmt(sz):>8s}  ~{tokens:>5d}tok  {len(r):>3d} results  ({desc})")

# =========================================================================
# B) Full pipeline vs raw FTS5 — same queries
# =========================================================================
print()
print("─" * 80)
print("B) FULL PIPELINE vs RAW FTS5 (overhead comparison)")
print("─" * 80)

for query, desc in [("Render", "high"), ("GetGBuffer", "medium"), ("FLumenSurfaceCacheData", "rare")]:
    r_raw, t_raw, sz_raw = measure(search_source, conn, query, limit=20)
    r_full, t_full, sz_full = measure(search_source_with_feedback, conn, query=query, limit=20)
    tok_raw = estimate_tokens(json.dumps(r_raw, default=str))
    tok_full = estimate_tokens(json.dumps(r_full, default=str))
    overhead = (t_full - t_raw) / max(t_raw, 0.001) * 100
    results.append(("B_raw", query, t_raw, sz_raw, tok_raw, len(r_raw), desc))
    results.append(("B_full", query, t_full, sz_full, tok_full, len(r_full), desc))
    print(f"  {query:30s} raw={t_raw*1000:6.0f}ms/{tok_raw:>5d}tok  full={t_full*1000:6.0f}ms/{tok_full:>5d}tok  overhead={overhead:+.0f}%")

# =========================================================================
# C) Clustered search — token reduction
# =========================================================================
print()
print("─" * 80)
print("C) CLUSTERED SEARCH (token reduction)")
print("─" * 80)

for query in ["Render", "FMaterial", "GetGBuffer"]:
    r_plain, t_plain, sz_plain = measure(
        search_source_with_feedback, conn, query=query, limit=20, cluster=False
    )
    r_clust, t_clust, sz_clust = measure(
        search_source_with_feedback, conn, query=query, limit=20, cluster=True
    )
    tok_plain = estimate_tokens(json.dumps(r_plain, default=str))
    tok_clust = estimate_tokens(json.dumps(r_clust, default=str))
    reduction = (1 - tok_clust / max(tok_plain, 1)) * 100
    results.append(("C_plain", query, t_plain, sz_plain, tok_plain, len(r_plain), ""))
    results.append(("C_cluster", query, t_clust, sz_clust, tok_clust, len(r_clust), ""))
    print(f"  {query:30s} plain={len(r_plain):>3d} results/{tok_plain:>5d}tok  cluster={len(r_clust):>3d}/{tok_clust:>5d}tok  reduction={reduction:.0f}%")

# =========================================================================
# D) Scope-filtered search — precision gain
# =========================================================================
print()
print("─" * 80)
print("D) SCOPE-FILTERED SEARCH (precision)")
print("─" * 80)

for scope in [
    {"block_type": "function"},
    {"block_type": "class"},
    {"block_type": "namespace"},
]:
    r, t, sz = measure(
        search_source_with_feedback, conn, query="Render", limit=20,
        scope_filter=scope,
    )
    tok = estimate_tokens(json.dumps(r, default=str))
    results.append(("D_scope", str(scope), t, sz, tok, len(r), ""))
    print(f"  {str(scope):40s} {t*1000:8.0f}ms  ~{tok:>5d}tok  {len(r):>3d} results")

# =========================================================================
# E) find_callers — token comparison
# =========================================================================
print()
print("─" * 80)
print("E) FIND_CALLERS (token cost)")
print("─" * 80)

# Inline find_callers implementation
def test_find_callers(conn, symbol, scope=None):
    t0 = time.perf_counter()
    results = search_source(conn, symbol, module=scope, limit=50)
    callers = []
    seen = set()
    sym_lower = symbol.lower()
    for r in results:
        brackets_all = load_bracket_index(conn, r['id'])
        if not brackets_all:
            continue
        top_blocks = {b['open_line']: b for b in brackets_all if b['depth'] == 1}
        row = get_source_by_path(conn, r['file_path'])
        if not row:
            continue
        lines = row['raw_content'].splitlines()
        for line_idx, line in enumerate(lines, start=1):
            if sym_lower not in line.lower():
                continue
            stripped = line.lstrip()
            if stripped.startswith('#include'):
                continue
            enclosing_top = None
            for tb_open, tb in top_blocks.items():
                if tb['open_line'] <= line_idx <= tb['close_line']:
                    enclosing_top = tb
                    break
            if not enclosing_top:
                continue
            bk = (r['id'], enclosing_top['open_line'])
            if bk in seen:
                continue
            bn = enclosing_top.get('block_name') or ''
            if sym_lower in bn.lower():
                sig = enclosing_top.get('signature') or ''
                if sig and line_idx <= enclosing_top['open_line'] + 2:
                    continue
            seen.add(bk)
            callers.append({
                'file_path': r['file_path'],
                'block_type': enclosing_top['block_type'],
                'block_name': enclosing_top.get('block_name'),
                'caller_line': line_idx,
            })
    elapsed = time.perf_counter() - t0
    return callers, elapsed

for symbol in ["SampleLumenCard", "BeginRenderPass", "GetGBuffer", "Render"]:
    callers, t = test_find_callers(conn, symbol)
    resp = json.dumps(callers, default=str)
    sz = len(resp.encode('utf-8'))
    tok = estimate_tokens(resp)
    results.append(("E_callers", symbol, t, sz, tok, len(callers), ""))
    print(f"  {symbol:30s} {t*1000:8.0f}ms  {sizeof_fmt(sz):>8s}  ~{tok:>5d}tok  {len(callers):>3d} callers")

# =========================================================================
# F) find_include_graph — token cost
# =========================================================================
print()
print("─" * 80)
print("F) FIND_INCLUDE_GRAPH (token cost)")
print("─" * 80)

test_files = [
    ("Engine/Source/Runtime/Renderer/Private/DeferredShadingRenderer.cpp", "large .cpp"),
    ("Engine/Source/Runtime/Engine/Public/SceneView.h", "large .h"),
    ("Engine/Shaders/Private/Lumen/SurfaceCache/LumenSurfaceCacheSampling.ush", "shader"),
]

for fpath, desc in test_files:
    row = conn.execute("SELECT id FROM source_files WHERE file_path = ?", (fpath,)).fetchone()
    if not row:
        print(f"  {fpath}: NOT FOUND")
        continue
    fid = row["id"]

    for direction in ["downstream", "upstream", "both"]:
        t0 = time.perf_counter()
        edges = []
        if direction in ("downstream", "both"):
            for r in conn.execute(
                "SELECT include_path, target_file_id FROM include_edges WHERE source_file_id = ?",
                (fid,),
            ).fetchall():
                edges.append({"include_path": r["include_path"], "direction": "downstream"})
        if direction in ("upstream", "both"):
            for r in conn.execute(
                "SELECT source_file_id FROM include_edges WHERE target_file_id = ?",
                (fid,),
            ).fetchall():
                edges.append({"source_file_id": r["source_file_id"], "direction": "upstream"})
        elapsed = time.perf_counter() - t0
        resp = json.dumps(edges, default=str)
        sz = len(resp.encode("utf-8"))
        tok = estimate_tokens(resp)
        results.append(("F_include", f"{desc}:{direction}", elapsed, sz, tok, len(edges), ""))
        print(f"  {desc:15s} {direction:12s} {elapsed*1000:8.1f}ms  ~{tok:>5d}tok  {len(edges):>3d} edges")

# =========================================================================
# G) Content retrieval — anchor vs full vs line-range
# =========================================================================
print()
print("─" * 80)
print("G) CONTENT RETRIEVAL (anchor vs full vs line-range)")
print("─" * 80)

for fpath, anchor, desc in [
    ("Engine/Source/Runtime/Renderer/Private/DeferredShadingRenderer.cpp", "Render", "large .cpp"),
    ("Engine/Source/Runtime/Engine/Public/SceneView.h", "FSceneView", "large .h"),
]:
    # Full read
    t0 = time.perf_counter()
    row = get_source_by_path(conn, fpath)
    t_full = time.perf_counter() - t0
    full_bytes = len(row["raw_content"].encode("utf-8"))
    full_tok = estimate_tokens(row["raw_content"])

    # Anchor read (500 chars)
    t0 = time.perf_counter()
    anchored = get_source_anchored(conn, fpath, anchor, context_chars=500)
    t_anchor = time.perf_counter() - t0
    anchor_bytes = len(anchored["content"].encode("utf-8")) if anchored else 0
    anchor_tok = estimate_tokens(anchored["content"]) if anchored else 0

    # Line range (100 lines)
    t0 = time.perf_counter()
    lines = row["raw_content"].splitlines()
    snippet = "\n".join(lines[99:199])
    t_range = time.perf_counter() - t0
    range_tok = estimate_tokens(snippet)

    results.append(("G_full", fpath, t_full, full_bytes, full_tok, 0, desc))
    results.append(("G_anchor", fpath, t_anchor, anchor_bytes, anchor_tok, 0, desc))

    print(f"  {desc:15s} full:  {t_full*1000:8.1f}ms  {sizeof_fmt(full_bytes):>8s}  ~{full_tok:>7d}tok")
    print(f"  {'':15s} anchor: {t_anchor*1000:8.1f}ms  {sizeof_fmt(anchor_bytes):>8s}  ~{anchor_tok:>7d}tok  ({full_tok/max(anchor_tok,1):.0f}x smaller)")
    print(f"  {'':15s} range:  {t_range*1000:8.1f}ms  ~{range_tok:>7d}tok")

# =========================================================================
# H) Skill-driven multi-step workflow simulation
# =========================================================================
print()
print("─" * 80)
print("H) SKILL WORKFLOW SIMULATION (3 searches + 2 extracts)")
print("─" * 80)

total_t = 0
total_tok = 0
total_bytes = 0
tool_calls = 0

# Step 1: Search for FSceneView
r, t, sz = measure(search_source_with_feedback, conn, query="FSceneView rendering pipeline", limit=10)
total_t += t; total_tok += estimate_tokens(json.dumps(r, default=str)); total_bytes += sz; tool_calls += 1
print(f"  Step 1 search: {t*1000:.0f}ms  ~{estimate_tokens(json.dumps(r, default=str))}tok")

# Step 2: Search for FViewUniformShaderParameters
r, t, sz = measure(search_source_with_feedback, conn, query="FViewUniformShaderParameters", limit=10)
total_t += t; total_tok += estimate_tokens(json.dumps(r, default=str)); total_bytes += sz; tool_calls += 1
print(f"  Step 2 search: {t*1000:.0f}ms  ~{estimate_tokens(json.dumps(r, default=str))}tok")

# Step 3: Search for SceneViewInitOptions
r, t, sz = measure(search_source_with_feedback, conn, raw_query='"FSceneViewInitOptions" AND "FSceneView"', limit=10)
total_t += t; total_tok += estimate_tokens(json.dumps(r, default=str)); total_bytes += sz; tool_calls += 1
print(f"  Step 3 raw:    {t*1000:.0f}ms  ~{estimate_tokens(json.dumps(r, default=str))}tok")

# Step 4: Anchor extract from SceneView.h
r, t, sz = measure(get_source_anchored, conn,
    "Engine/Source/Runtime/Engine/Public/SceneView.h", "class FSceneView", context_chars=2000)
total_t += t; total_tok += estimate_tokens(r["content"] if r else ""); total_bytes += sz; tool_calls += 1
print(f"  Step 4 anchor: {t*1000:.0f}ms  ~{estimate_tokens(r['content'] if r else '')}tok")

# Step 5: find_callers
callers, t = test_find_callers(conn, "FViewUniformShaderParameters")
total_t += t
c_tok = estimate_tokens(json.dumps(callers[:10], default=str))  # typical: top 10
total_tok += c_tok; tool_calls += 1
print(f"  Step 5 callers: {t*1000:.0f}ms  ~{c_tok}tok (top 10 of {len(callers)})")

print(f"\n  WORKFLOW TOTAL: {total_t*1000:.0f}ms  ~{total_tok}tok  {tool_calls} tool calls  {sizeof_fmt(total_bytes)} response")

# =========================================================================
# SUMMARY
# =========================================================================
print()
print("=" * 80)
print("SUMMARY: TOKEN COST PER OPERATION TYPE")
print("=" * 80)
print(f"\n{'Category':<12} {'Query':<35} {'Time':>8} {'Size':>10} {'~Tokens':>10} {'Results':>8}")
print("-" * 90)

for cat, query, t, sz, tok, n, desc in sorted(results, key=lambda x: x[2], reverse=True):
    print(f"  {cat:<10} {query[:33]:<33} {t*1000:>7.0f}ms {sizeof_fmt(sz):>10} {tok:>10} {n:>8}")

conn.close()
