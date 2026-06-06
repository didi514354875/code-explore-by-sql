"""Build the three-table index for source code.

Pipeline per file:
  1. Dispatch by file extension -> LanguageConfig
  2. Read file content -> upsert into file_content (FTS5)
  3. bracket_scanner -> bracket blocks
  4. symbol_analyzer -> SymbolDef[] with QN normalization + decoration metadata
  5. edge_extractor -> StrictEdge[] (4 types only)
  6. Write symbol_index + strict_edges

Usage:
  python -m code_source_sql.build_db <source_root> <db_path> [options]
"""

from __future__ import annotations

import argparse
import hashlib
import time
from pathlib import Path

from .configs import FrameworkConfig, LanguageConfig, ProjectConfig, get_language
from .unreal_rules import make_unreal_framework

EXCLUDE_PARTS = {".git", ".vs", "Binaries", "Build", "DerivedDataCache", "Intermediate", "Saved", "ThirdParty"}

_INVALID_MODULE_NAMES = frozenset({
    "Private", "Public", "Classes", "Inc", "Src", "Source",
    "Include", "Internal", "Tests", "Test",
})


def iter_source_files(
    root: Path,
    extensions: set[str],
    exclude_parts: frozenset[str],
    limit: int | None = None,
) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in extensions:
            continue
        if set(path.parts) & exclude_parts:
            continue
        files.append(path)
    if limit:
        files = files[:limit]
    return files


def infer_module_name(path: Path, source_marker: str = "Source", categories: set[str] | None = None) -> str | None:
    parts = path.parts
    if source_marker not in parts:
        return None
    idx = parts.index(source_marker)
    cats = categories or set()
    max_offset = len(parts) - idx - 1
    for offset in range(1, max_offset):
        candidate = parts[idx + offset]
        if candidate in _INVALID_MODULE_NAMES:
            continue
        if candidate in cats:
            continue
        return candidate
    return None


def _get_configs(
    project: ProjectConfig,
) -> dict[str, tuple[LanguageConfig, FrameworkConfig]]:
    """Build a mapping from file extension -> (LanguageConfig, FrameworkConfig).

    Framework selection is per-language:
    - C++ files in an Unreal project get the Unreal framework (UCLASS, UFUNCTION, etc.)
    - C# files in an Unreal project get the generic framework (no UE C++ rules)
    - All files in a generic project get the generic framework
    """
    from .configs import make_generic_framework

    # Build framework(s)
    fw_name = project.framework_name
    if fw_name == "unreal":
        fw_unreal = make_unreal_framework()
    else:
        fw_unreal = None
    fw_generic = make_generic_framework()

    # Build languages (registry-based)
    lang_names = set(project.extension_to_language.values())
    langs: dict[str, LanguageConfig] = {}
    for ln in lang_names:
        langs[ln] = get_language(ln)

    # Map extension -> (lang, fw)
    # C# files always use generic framework even in Unreal projects,
    # since UE C++ rules (UFUNCTION, UCLASS, etc.) don't apply to C#.
    result: dict[str, tuple[LanguageConfig, FrameworkConfig]] = {}
    for ext, ln in project.extension_to_language.items():
        if fw_unreal and ln == "cpp":
            result[ext] = (langs[ln], fw_unreal)
        else:
            result[ext] = (langs[ln], fw_generic)

    return result


def _process_file(
    file_id: int,
    content: str,
    lines: list[str],
    lang: LanguageConfig,
    fw: FrameworkConfig,
) -> tuple[list, list, list]:
    """Process a single file: extract symbols + edges."""
    from .edge_extractor import extract_edges
    from .symbol_analyzer import analyze_file

    symbols, extras = analyze_file(lines, file_id, lang, fw)
    edges = extract_edges(symbols, extras, lines, fw, lang)

    return symbols, extras, edges


def build_index(
    root: Path,
    db_path: Path,
    limit: int | None = None,
    project: ProjectConfig | None = None,
) -> int:
    from .db import commit, connect, initialize_schema, insert_edges, insert_extra_symbols, insert_symbols, upsert_file

    if project is None:
        # Default to generic project config
        from .configs import make_generic_project
        project = make_generic_project()

    conn = connect(db_path)
    initialize_schema(conn)

    # Clear existing data for clean rebuild
    conn.execute("DELETE FROM strict_edges")
    conn.execute("DELETE FROM symbol_index")
    conn.execute("DELETE FROM file_content")
    conn.commit()

    extensions = set(project.extension_to_language.keys())
    ext_configs = _get_configs(project)

    files = iter_source_files(root, extensions, project.exclude_parts, limit)
    print(f"Indexing {len(files)} files from {root}...", flush=True)
    t_start = time.time()

    count = 0
    sym_count = 0
    edge_count = 0
    batch_size = 200

    for _, path in enumerate(files):
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        digest = hashlib.sha256(content.encode("utf-8", errors="replace")).hexdigest()
        rel = str(path.relative_to(root)).replace("\\", "/")
        module = infer_module_name(path, project.source_marker, project.categories)

        # Dispatch by file extension
        ext = path.suffix.lower()
        from .configs import make_generic_framework
        lang, fw_for_file = ext_configs.get(ext, (get_language("cpp"), make_generic_framework()))

        file_id = upsert_file(conn, rel, module, content, digest, language=lang.name)
        lines = content.split("\n")

        sym_rows, extra_rows, edge_rows = _process_file(file_id, content, lines, lang, fw_for_file)

        insert_symbols(conn, sym_rows)
        insert_extra_symbols(conn, extra_rows)
        insert_edges(conn, edge_rows)

        sym_count += len(sym_rows) + len(extra_rows)
        edge_count += len(edge_rows)
        count += 1

        if count % batch_size == 0:
            commit(conn)
            elapsed = time.time() - t_start
            rate = count / elapsed if elapsed > 0 else 0
            print(f"  {count}/{len(files)} ({count/len(files)*100:.0f}%) "
                  f"{rate:.0f} files/s, {sym_count:,} symbols, {edge_count:,} edges", flush=True)

    commit(conn)
    elapsed = time.time() - t_start
    print(f"Done: {count} files, {sym_count:,} symbols, {edge_count:,} edges in {elapsed:.1f}s", flush=True)

    # Cross-language edge cleanup: remove edges where source and target
    # symbols are defined in different languages
    cross_before = conn.execute("SELECT COUNT(*) AS c FROM strict_edges").fetchone()["c"]
    conn.execute("""
        DELETE FROM strict_edges WHERE id IN (
            SELECT e.id FROM strict_edges e
            JOIN symbol_index si_src ON e.source_qn = si_src.qualified_name
            JOIN symbol_index si_tgt ON e.target_qn = si_tgt.qualified_name
            WHERE si_src.language != si_tgt.language
        )
    """)
    conn.commit()
    cross_after = conn.execute("SELECT COUNT(*) AS c FROM strict_edges").fetchone()["c"]
    removed = cross_before - cross_after
    if removed > 0:
        print(f"Cross-language edges removed: {removed:,} ({cross_before:,} -> {cross_after:,})", flush=True)

    # Print summary stats
    fc = conn.execute("SELECT COUNT(*) AS c FROM file_content").fetchone()["c"]
    sc = conn.execute("SELECT COUNT(*) AS c FROM symbol_index").fetchone()["c"]
    ec = conn.execute("SELECT COUNT(*) AS c FROM strict_edges").fetchone()["c"]
    print(f"DB stats: {fc:,} files, {sc:,} symbols, {ec:,} edges", flush=True)

    # Print edge type breakdown
    for row in conn.execute(
        "SELECT edge_type, COUNT(*) AS c FROM strict_edges GROUP BY edge_type ORDER BY c DESC"
    ).fetchall():
        print(f"  {row['edge_type']}: {row['c']:,}", flush=True)

    # Print language breakdown
    for row in conn.execute(
        "SELECT language, COUNT(*) AS c FROM symbol_index GROUP BY language ORDER BY c DESC"
    ).fetchall():
        print(f"  symbols[{row['language']}]: {row['c']:,}", flush=True)

    conn.close()
    return count


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build SQLite index for source code (three-table architecture)."
    )
    parser.add_argument("root", type=Path, help="Source root directory")
    parser.add_argument("db", type=Path, help="SQLite database path")
    parser.add_argument("--limit", type=int, default=None, help="File limit for testing")
    parser.add_argument(
        "--source-marker", default="",
        help="Path component marking source root (default: auto-detect)"
    )
    parser.add_argument(
        "--categories", default="",
        help="Comma-separated category dirs to skip after source marker"
    )
    parser.add_argument(
        "--framework", default="generic",
        choices=["unreal", "generic"],
        help="Framework rules to apply (default: generic)"
    )
    args = parser.parse_args()

    cats = {c.strip() for c in args.categories.split(",") if c.strip()} or None

    if args.framework == "unreal":
        fw = make_unreal_framework()
        from .configs import make_unreal_project
        base_project = make_unreal_project(framework=fw)
        source_marker = args.source_marker or "Source"
    else:
        from .configs import make_generic_framework, make_generic_project
        fw = make_generic_framework()
        base_project = make_generic_project()
        source_marker = args.source_marker

    project = ProjectConfig(
        extension_to_language=base_project.extension_to_language,
        exclude_parts=base_project.exclude_parts,
        source_marker=source_marker,
        categories=frozenset(cats) if cats else frozenset(),
        invalid_module_names=base_project.invalid_module_names,
        framework_name=fw.name,
    )

    build_index(args.root, args.db, args.limit, project)


if __name__ == "__main__":
    main()
