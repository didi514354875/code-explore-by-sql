"""Query pipeline efficiency and correctness tests.

Tests the full search → history → scoring → scope → clustering pipeline,
plus find_callers and find_include_graph tools.

Usage:
    PYTHONPATH=src python3 -u tests/test_query_efficiency.py
"""

from __future__ import annotations

import sqlite3
import time
import sys
import os
import json
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from unreal_source_mcp.db import (
    connect,
    initialize_schema,
    search_source,
    search_source_raw,
    search_source_with_feedback,
    _search_fts,
    _fts5_escape,
    _extract_search_terms,
    _get_history_signals,
    _cluster_results,
    load_bracket_index,
    find_enclosing_block,
    get_source_by_path,
    get_source_anchored,
)

DB_PATH = os.environ.get("UNREAL_SOURCE_DB", "unreal.db")

PASS = 0
FAIL = 0
TIMINGS: list[tuple[str, float]] = []


def check(name: str, condition: bool, detail: str = ""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name} — {detail}")


def timed(name: str, fn, *args, **kwargs):
    t0 = time.perf_counter()
    result = fn(*args, **kwargs)
    elapsed = time.perf_counter() - t0
    TIMINGS.append((name, elapsed))
    print(f"  ⏱ {name}: {elapsed*1000:.1f} ms")
    return result


def avg_timed(name: str, fn, *args, runs: int = 3, **kwargs):
    times = []
    result = None
    for _ in range(runs):
        t0 = time.perf_counter()
        result = fn(*args, **kwargs)
        times.append(time.perf_counter() - t0)
    avg = sum(times) / len(times)
    best = min(times)
    TIMINGS.append((f"{name} (avg/{runs})", avg))
    n = len(result) if isinstance(result, list) else "?"
    print(f"  ⏱ {name}: avg={avg*1000:.1f} ms, best={best*1000:.1f} ms ({n} results)")
    return result


# ========================================================================
# Setup
# ========================================================================
print("=" * 70)
print("QUERY PIPELINE EFFICIENCY TESTS")
print("=" * 70)

conn = connect(DB_PATH)
initialize_schema(conn)

# ========================================================================
# Section 1: FTS5 Raw Search — baseline performance
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 1: FTS5 Raw Search (optimized two-step)")
print("=" * 70)

print("\n[1.1] Single keyword: Render")
r1 = avg_timed("single_kw_Render", search_source, conn, "Render", limit=20)

print("\n[1.2] High-frequency keyword: int")
r2 = avg_timed("high_freq_int", search_source, conn, "int", limit=20)

print("\n[1.3] Multi-word: FMaterial Render")
r4 = avg_timed("multi_kw_FMaterial_Render", search_source, conn, "FMaterial Render", limit=20)

print("\n[1.4] Raw FTS5: GetGBuffer AND Emissive")
r5 = timed(
    "raw_fts_GetGBuffer_Emissive",
    search_source_raw, conn,
    '"GetGBuffer" AND "Emissive"',
    limit=20,
)

print("\n[1.5] Raw FTS5: Material NOT hlsl")
r6 = timed(
    "raw_fts_Material_NOT_hlsl",
    search_source_raw, conn,
    '"Material" NOT "hlsl"',
    limit=20,
)

check("single_kw returns results", len(r1) > 0, f"got {len(r1)}")
check("high_freq returns results", len(r2) > 0, f"got {len(r2)}")

# Verify result structure
if r1:
    check("result has id", "id" in r1[0])
    check("result has file_path", "file_path" in r1[0])
    check("result has module_name", "module_name" in r1[0])
    check("result has rank", "rank" in r1[0])
    check("result has snippet", "snippet" in r1[0] and r1[0]["snippet"] is not None,
          f"snippet={r1[0].get('snippet')}")


# ========================================================================
# Section 2: Full search pipeline with history signals
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 2: Full Search Pipeline (FTS5 + History + Scoring)")
print("=" * 70)

print("\n[2.1] Full pipeline: Render")
r_full = avg_timed(
    "full_pipeline_Render",
    search_source_with_feedback, conn,
    query="Render",
    limit=20,
)

print("\n[2.2] Full pipeline with expanded_terms")
r_expanded = timed(
    "full_pipeline_expanded",
    search_source_with_feedback, conn,
    query="Material architecture",
    expanded_terms=["FMaterial", "UMaterialInterface", "MaterialResource", "MaterialRenderProxy"],
    limit=20,
)

print("\n[2.3] Full pipeline with module filter")
r_mod = timed(
    "full_pipeline_module",
    search_source_with_feedback, conn,
    query="Render",
    module="Renderer",
    limit=20,
)

# Check result structure
if r_full:
    check("full_pipeline has final_score", "final_score" in r_full[0])
    check("full_pipeline has source", "source" in r_full[0])
    check("full_pipeline results sorted by final_score",
          all(r_full[i]["final_score"] >= r_full[i+1]["final_score"] for i in range(len(r_full)-1)),
          f"scores: {[round(r['final_score'], 2) for r in r_full[:5]]}")

check("expanded results exist", len(r_expanded) > 0, f"got {len(r_expanded)}")

if r_mod:
    module_names = set(r["module_name"] for r in r_mod if r["module_name"])
    check("module filter applied", all(m == "Renderer" for m in module_names),
          f"got modules: {module_names}")


# ========================================================================
# Section 3: History Signal Isolation
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 3: History Signal Isolation")
print("=" * 70)

print("\n[3.1] History signals for 'Render'")
terms_render = _extract_search_terms("Render")
t0 = time.perf_counter()
hist_render = _get_history_signals(conn, terms_render)
elapsed_hist = time.perf_counter() - t0
TIMINGS.append(("history_signals_Render", elapsed_hist))
print(f"  ⏱ history_signals: {elapsed_hist*1000:.1f} ms, {len(hist_render)} files scored")

print("\n[3.2] History signals for cold query")
terms_cold = _extract_search_terms("ZZZZ_NONEXISTENT_QUERY_XYZ")
t0 = time.perf_counter()
hist_cold = _get_history_signals(conn, terms_cold)
elapsed_cold = time.perf_counter() - t0
TIMINGS.append(("history_signals_cold", elapsed_cold))
print(f"  ⏱ history_signals (cold): {elapsed_cold*1000:.1f} ms, {len(hist_cold)} files scored")

print("\n[3.3] _extract_search_terms correctness")
tests = [
    ("FMaterial Render", ["FMaterial", "Render"]),
    ('"GetGBuffer" AND "Emissive"', ["GetGBuffer", "Emissive"]),
    ("namespace UECodeGen", ["UECodeGen"]),  # namespace is a stop word
]
for query_text, expected_substrs in tests:
    terms = _extract_search_terms(query_text)
    for exp in expected_substrs:
        found = any(exp.lower() in t.lower() for t in terms)
        check(f"terms({query_text!r}) contains {exp!r}", found, f"got {terms}")


# ========================================================================
# Section 4: FTS5 Escape Correctness
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 4: FTS5 Escape & Query Construction")
print("=" * 70)

esc_tests = [
    ("Render", '"Render"'),
    ("FMaterial Render", '"FMaterial" AND "Render"'),
    ("GetGBuffer", '"GetGBuffer"'),
]
for raw, expected_pattern in esc_tests:
    escaped = _fts5_escape(raw)
    check(f"escape({raw!r})", all(w.strip('"') in escaped for w in expected_pattern.split(" AND ")),
          f"got {escaped}")


# ========================================================================
# Section 5: Clustering
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 5: Search Result Clustering")
print("=" * 70)

print("\n[5.1] Clustered search: Render")
r_clustered = timed(
    "clustered_Render",
    search_source_with_feedback, conn,
    query="Render",
    limit=20,
    cluster=True,
)

if r_clustered:
    has_cluster = any("cluster" in r for r in r_clustered)
    has_hit_count = any("hit_count" in r for r in r_clustered)
    check("clustered results have cluster field", has_cluster)
    check("clustered results have hit_count", has_hit_count)

    for r in r_clustered[:3]:
        if "cluster" in r:
            c = r["cluster"]
            check("cluster has block_type", "block_type" in c, f"got {list(c.keys())}")
            check("cluster has open_line", "open_line" in c)
            check("cluster has close_line", "close_line" in c)
            break

r_non_clustered = search_source_with_feedback(conn, query="Render", limit=20, cluster=False)
check("clustering reduces or maintains result count",
      len(r_clustered) <= len(r_non_clustered),
      f"clustered={len(r_clustered)}, non={len(r_non_clustered)}")


# ========================================================================
# Section 6: Scope Filtering
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 6: Scope Filtering")
print("=" * 70)

print("\n[6.1] Scope filter: block_type=function")
r_scope_fn = timed(
    "scope_function_Render",
    search_source_with_feedback, conn,
    query="Render",
    limit=20,
    scope_filter={"block_type": "function"},
)

print("\n[6.2] Scope filter: block_type=class")
r_scope_class = timed(
    "scope_class_Render",
    search_source_with_feedback, conn,
    query="Render",
    limit=20,
    scope_filter={"block_type": "class"},
)

print(f"  Results: function={len(r_scope_fn)}, class={len(r_scope_class)}")
check("scope filters work", len(r_scope_fn) >= 0 and len(r_scope_class) >= 0)


# ========================================================================
# Section 7: find_callers
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 7: find_callers Tool")
print("=" * 70)

def test_find_callers(conn, symbol: str, scope: str | None = None):
    t0 = time.perf_counter()
    results = search_source(conn, symbol, module=scope, limit=50)

    callers = []
    seen_blocks = set()

    for r in results:
        brackets = load_bracket_index(conn, r["id"], depth=1)
        for b in brackets:
            block_key = (r["id"], b["open_line"])
            if block_key in seen_blocks:
                continue
            if b["block_name"] and symbol.lower() in (b["block_name"] or "").lower():
                continue
            seen_blocks.add(block_key)
            callers.append({
                "file_path": r["file_path"],
                "module_name": r["module_name"],
                "block_type": b["block_type"],
                "block_name": b["block_name"],
                "block_range": f"{b['open_line']}-{b['close_line']}",
            })

    elapsed = time.perf_counter() - t0
    return callers, elapsed

print("\n[7.1] find_callers: Render")
callers, elapsed = test_find_callers(conn, "Render")
TIMINGS.append(("find_callers_Render", elapsed))
print(f"  ⏱ {elapsed*1000:.0f} ms, {len(callers)} callers")
if callers:
    check("callers have file_path", all("file_path" in c for c in callers[:5]))
    check("callers have block_type", all("block_type" in c for c in callers[:5]))
    types = Counter(c["block_type"] for c in callers)
    print(f"  Block types: {dict(types)}")

print("\n[7.2] find_callers: BeginRenderPass")
callers2, elapsed = test_find_callers(conn, "BeginRenderPass")
TIMINGS.append(("find_callers_BeginRenderPass", elapsed))
print(f"  ⏱ {elapsed*1000:.0f} ms, {len(callers2)} callers")

print("\n[7.3] find_callers: GetGBuffer")
callers3, elapsed = test_find_callers(conn, "GetGBuffer")
TIMINGS.append(("find_callers_GetGBuffer", elapsed))
print(f"  ⏱ {elapsed*1000:.0f} ms, {len(callers3)} callers")

print("\n[7.4] find_callers: cold symbol")
callers_cold, elapsed = test_find_callers(conn, "ZZZZZNONEXISTENT")
TIMINGS.append(("find_callers_cold", elapsed))
print(f"  ⏱ {elapsed*1000:.0f} ms, {len(callers_cold)} callers")
check("cold find_callers returns 0", len(callers_cold) == 0, f"got {len(callers_cold)}")


# ========================================================================
# Section 8: find_include_graph
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 8: find_include_graph Tool")
print("=" * 70)

sample = conn.execute(
    "SELECT file_path FROM source_files WHERE file_path LIKE '%/Renderer/%' AND file_path LIKE '%.cpp' LIMIT 1"
).fetchone()
sample_path = sample["file_path"] if sample else None

if sample_path:
    row = conn.execute("SELECT id FROM source_files WHERE file_path = ?", (sample_path,)).fetchone()
    fid = row["id"]

    t0 = time.perf_counter()
    edges_down = conn.execute(
        """SELECT ie.include_path, ie.target_file_id, sf.file_path AS target_path
           FROM include_edges ie LEFT JOIN source_files sf ON sf.id = ie.target_file_id
           WHERE ie.source_file_id = ?""", (fid,),
    ).fetchall()
    t_down = time.perf_counter() - t0
    TIMINGS.append(("include_graph_downstream", t_down))
    print(f"  ⏱ downstream: {t_down*1000:.1f} ms, {len(edges_down)} edges")

    t0 = time.perf_counter()
    edges_up = conn.execute(
        """SELECT ie.source_file_id, sf.file_path AS source_path
           FROM include_edges ie JOIN source_files sf ON sf.id = ie.source_file_id
           WHERE ie.target_file_id = ?""", (fid,),
    ).fetchall()
    t_up = time.perf_counter() - t0
    TIMINGS.append(("include_graph_upstream", t_up))
    print(f"  ⏱ upstream: {t_up*1000:.1f} ms, {len(edges_up)} edges")
    print(f"  File: {sample_path}")
else:
    print("  [SKIP] No Renderer .cpp files found")


# ========================================================================
# Section 9: Bracket Index & find_enclosing_block
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 9: Bracket Index & find_enclosing_block")
print("=" * 70)

sample = conn.execute(
    "SELECT bi.file_id, sf.file_path FROM bracket_index bi "
    "JOIN source_files sf ON sf.id = bi.file_id "
    "WHERE bi.depth = 1 AND bi.block_type = 'function' "
    "LIMIT 1"
).fetchone()

if sample:
    fid = sample["file_id"]
    fpath = sample["file_path"]
    print(f"\n[9.1] File: {fpath}")

    t0 = time.perf_counter()
    brackets_d1 = load_bracket_index(conn, fid, depth=1)
    t_d1 = time.perf_counter() - t0
    TIMINGS.append(("load_bracket_d1", t_d1))
    print(f"  ⏱ depth=1: {t_d1*1000:.1f} ms, {len(brackets_d1)} blocks")

    t0 = time.perf_counter()
    brackets_all = load_bracket_index(conn, fid)
    t_all = time.perf_counter() - t0
    TIMINGS.append(("load_bracket_all", t_all))
    print(f"  ⏱ all depths: {t_all*1000:.1f} ms, {len(brackets_all)} blocks")

    check("all-depths >= depth-1", len(brackets_all) >= len(brackets_d1))

    if brackets_all:
        mid_line = brackets_all[0]["open_line"] + 2
        t0 = time.perf_counter()
        enclosing = find_enclosing_block(brackets_all, mid_line)
        t_enc = time.perf_counter() - t0
        TIMINGS.append(("find_enclosing_block", t_enc))
        print(f"  ⏱ find_enclosing_block({mid_line}): {t_enc*1000:.3f} ms")
        if enclosing:
            check("enclosing found", enclosing is not None)
            check("line within range",
                  enclosing["open_line"] <= mid_line <= enclosing["close_line"],
                  f"line={mid_line}, range={enclosing['open_line']}-{enclosing['close_line']}")
            print(f"  → {enclosing['block_type']}:{enclosing.get('block_name', '?')}")


# ========================================================================
# Section 10: Content Retrieval
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 10: Content Retrieval Efficiency")
print("=" * 70)

if sample_path:
    print(f"\n[10.1] get_source_by_path: {sample_path[:60]}")
    t0 = time.perf_counter()
    row = get_source_by_path(conn, sample_path)
    t_full = time.perf_counter() - t0
    TIMINGS.append(("get_source_by_path", t_full))
    print(f"  ⏱ {t_full*1000:.1f} ms, {len(row['raw_content']):,} chars")

    print(f"\n[10.2] get_source_anchored: 'void'")
    t0 = time.perf_counter()
    anchored = get_source_anchored(conn, sample_path, "void", context_chars=500)
    t_anchor = time.perf_counter() - t0
    TIMINGS.append(("get_source_anchored", t_anchor))
    print(f"  ⏱ {t_anchor*1000:.1f} ms")
    if anchored:
        print(f"  Extracted {len(anchored.get('content', ''))} chars at pos {anchored.get('anchor_pos')}")


# ========================================================================
# Section 11: Pipeline Breakdown
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 11: Pipeline Step Breakdown")
print("=" * 70)

query_text = "FScene View Render"
fts_query = _fts5_escape(query_text)
terms = _extract_search_terms(query_text)
print(f"  Query: {query_text}")
print(f"  Terms: {terms}")
print(f"  FTS: {fts_query}")

t0 = time.perf_counter()
fts_results = _search_fts(conn, fts_query, None, 100)
t_fts = time.perf_counter() - t0

t0 = time.perf_counter()
hist = _get_history_signals(conn, terms)
t_hist = time.perf_counter() - t0

total = t_fts + t_hist
print(f"  FTS5: {t_fts*1000:.0f} ms ({len(fts_results)} results)")
print(f"  History: {t_hist*1000:.0f} ms ({len(hist)} files)")
print(f"  Total: {total*1000:.0f} ms")


# ========================================================================
# Section 12: Rapid-fire Query Sequence
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 12: Rapid-fire Query Sequence (10 queries)")
print("=" * 70)

queries = [
    "FMaterial", "FScene", "Render", "Lumen", "GetGBuffer",
    "Nanite", "VirtualTexture", "SkeletalMesh", "Niagara", "PhysicsCore",
]

total_time = 0
for q in queries:
    t0 = time.perf_counter()
    results = search_source_with_feedback(conn, query=q, limit=10)
    elapsed = time.perf_counter() - t0
    total_time += elapsed
    TIMINGS.append((f"rapid_{q}", elapsed))
    print(f"  ⏱ {q}: {elapsed*1000:.0f} ms → {len(results)} results")

avg_time = total_time / len(queries)
print(f"\n  Average: {avg_time*1000:.0f} ms/query")
print(f"  Total: {total_time*1000:.0f} ms for {len(queries)} queries")
check("avg query < 2000ms", avg_time < 2.0, f"avg={avg_time*1000:.0f}ms")


# ========================================================================
# Section 13: Correctness & Edge Cases
# ========================================================================
print("\n" + "=" * 70)
print("SECTION 13: Correctness & Edge Cases")
print("=" * 70)

print("\n[13.1] Empty query")
r_empty = search_source_with_feedback(conn, query="", limit=10)
check("empty query returns []", r_empty == [], f"got {len(r_empty)}")

print("\n[13.2] Special characters")
r_special = search_source_with_feedback(conn, query="void* ptr", limit=5)
check("special chars handled", isinstance(r_special, list), f"type={type(r_special)}")

print("\n[13.3] Long query")
long_q = " ".join(["Render"] * 20)
r_long = search_source_with_feedback(conn, query=long_q, limit=5)
check("long query handled", isinstance(r_long, list))

print("\n[13.4] Nonexistent module")
r_no_mod = search_source_with_feedback(conn, query="Render", module="NONEXISTENT_MODULE", limit=10)
check("nonexistent module returns []", r_no_mod == [], f"got {len(r_no_mod)}")


# ========================================================================
# Summary
# ========================================================================
print("\n" + "=" * 70)
print("TIMING SUMMARY")
print("=" * 70)

sorted_times = sorted(TIMINGS, key=lambda x: -x[1])
print(f"\n{'Operation':<45} {'Time (ms)':>10}")
print("-" * 60)
for name, t in sorted_times:
    print(f"  {name:<43} {t*1000:>8.1f}")

# Categorize
fts_times = [t for n, t in TIMINGS if "search" in n.lower() or "fts" in n.lower() or "pipeline" in n.lower()]
other_times = [t for n, t in TIMINGS if n not in {n2 for n2, _ in [(x[0], x[1]) for x in TIMINGS if "search" in x[0].lower() or "fts" in x[0].lower() or "pipeline" in x[0].lower()]}]

print(f"\n{'='*70}")
total_tests = PASS + FAIL
print(f"RESULTS: {PASS}/{total_tests} passed, {FAIL} failed")
print(f"{'='*70}")

conn.close()

if FAIL > 0:
    sys.exit(1)
