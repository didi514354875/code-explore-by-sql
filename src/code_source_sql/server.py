"""MCP server for source code navigation — five tools.

Tool 1: read_symbol(qualified_name)
  - Lookup by qualified name, returns identity + code/signature

Tool 2: search_fts_tool(keyword, path_filter)
  - FTS5 search, returns located blocks with code preview

Tool 3: read_file_range(file_path, start_line, end_line)
  - Read by position, returns code with symbol metadata

Tool 4: get_directory_structure()
  - Module/file counts from index

Tool 5: list_databases()
  - List available databases and their stats
"""

from __future__ import annotations

import os
import sqlite3
import threading
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
    initialize_schema,
)
from .db import (
    get_directory_structure as db_get_directory_structure,
)
from .db import (
    read_file_range as db_read_file_range,
)
from .db import (
    read_symbol as db_read_symbol,
)
from .db import (
    search_fts as db_search_fts,
)

mcp = FastMCP("code-source-sql")

# ── 多数据库注册表 ──────────────────────────────────────────────────


def _parse_db_registry() -> dict[str, str]:
    """从环境变量解析数据库注册表。

    CODE_SOURCE_DBS 格式（冒号分隔的路径列表）：
      "/data/unreal.db:/data/mygame.db:/data/lib.db"
    别名从路径的文件主干名（不含扩展名）自动生成：
      "unreal", "mygame", "lib"

    CODE_SOURCE_DB 仍然作为主库（默认库），同时加入注册表。
    """
    registry: dict[str, str] = {}

    # 主库 — CODE_SOURCE_DB
    primary = os.environ.get("CODE_SOURCE_DB", "code_source.db")
    primary_alias = Path(primary).stem  # e.g. "unreal" from "unreal.db"
    registry[primary_alias] = primary
    registry[""] = primary  # 空字符串 → 主库

    # 附加库 — CODE_SOURCE_DBS
    extra = os.environ.get("CODE_SOURCE_DBS", "")
    if extra:
        for path_str in extra.split(":"):
            path_str = path_str.strip()
            if not path_str:
                continue
            alias = Path(path_str).stem
            # 别名冲突时后者覆盖（概率极低，用户自行保证不重名）
            registry[alias] = path_str

    return registry


_DB_REGISTRY = _parse_db_registry()

# ── 连接缓存 ────────────────────────────────────────────────────────

_conn_cache: dict[str, sqlite3.Connection] = {}
_conn_lock = threading.Lock()


def _get_conn(db_alias: str = "") -> sqlite3.Connection:
    """按别名获取数据库连接，带缓存。"""
    db_path = _DB_REGISTRY.get(db_alias)
    if db_path is None:
        # 别名不存在 → 回退主库
        db_path = _DB_REGISTRY[""]

    with _conn_lock:
        conn = _conn_cache.get(db_path)
        if conn is not None:
            try:
                conn.execute("SELECT 1")
                return conn
            except Exception:
                # 连接已失效，移除缓存
                del _conn_cache[db_path]

        conn = connect(db_path)
        initialize_schema(conn)
        _conn_cache[db_path] = conn
        return conn


# ── 工具实现 ─────────────────────────────────────────────────────────


@mcp.tool()
def list_databases() -> dict[str, Any]:
    """List available databases and their stats.

    Returns the registry of databases the server can access.
    Use the 'alias' value as the 'db' parameter in other tools.
    The first entry is the default database (used when db is omitted).
    """
    results = []
    seen_paths: set[str] = set()
    for alias, path in _DB_REGISTRY.items():
        if alias == "" or path in seen_paths:
            continue
        seen_paths.add(path)

        entry: dict[str, Any] = {"alias": alias, "path": path}
        try:
            conn = _get_conn(alias)
            total = conn.execute(
                "SELECT COUNT(*) AS c FROM file_content"
            ).fetchone()["c"]
            sym_total = conn.execute(
                "SELECT COUNT(*) AS c FROM symbol_index"
            ).fetchone()["c"]
            entry["total_files"] = total
            entry["total_symbols"] = sym_total
        except Exception as e:
            entry["error"] = str(e)
        results.append(entry)

    return {"default": _DB_REGISTRY.get("", ""), "databases": results}


@mcp.tool()
def read_symbol(
    qualified_name: str,
    view: str = "full",
    expand_item: list[str] | None = None,
    db: str = "",
) -> dict[str, Any]:
    """Read a symbol's source code by qualified name.

    Accepts qualified names like 'ClassName::MethodName' or short names.
    Supports fuzzy matching: 'MethodName' matches 'ClassName::MethodName'.

    view: "full" (default) = complete code, "signature" = summary, "meta" = identity only.
    expand_item: optional ranking hints for ambiguous matches.
    db: database alias (from list_databases). Default: primary database.

    Returns dict with {qn, type, file, range, code?, alt?} or {error, query, fts?}.
    """
    conn = _get_conn(db)
    entries = db_read_symbol(conn, qualified_name, view=view, expand_item=expand_item)
    if not entries:
        fts_results = db_search_fts(conn, qualified_name, limit=5)
        if fts_results:
            return {
                "error": "not_found",
                "query": qualified_name,
                "fts": [
                    {"file": r["file"], "line": r["line"], "block": r.get("block")}
                    for r in fts_results[:5]
                ],
            }
        return {"error": "not_found", "query": qualified_name}

    result = entries[0]
    if len(entries) > 1:
        result["alt"] = entries[1:5]
    return result


@mcp.tool()
def search_fts_tool(
    keyword: str = "",
    path_filter: str = "",
    expand_item: list[str] | None = None,
    raw_query: str = "",
    db: str = "",
) -> list[dict[str, Any]]:
    """Locate code blocks by keyword or raw FTS5 query.

    Two query modes (use one):
    - keyword: auto-escaped AND of tokens. Simple, safe. Example: "AddDynamic"
    - raw_query: full FTS5 MATCH expression. Column filters, OR, NOT.
      Example: '(file_path : "Character.h") AND "BeginPlay"'

    FTS5 columns: file_path, module_name, content (all trigram, ≥3 chars).

    raw_query operators:
      AND  →  '"AddDynamic" AND "UObject"'
      OR   →  '"AActor" OR "APawn"'
      NOT  →  '"Update" NOT "Test"'
      Column filter →  '(file_path : "Shader.h") AND "FShaderType"'
      Module filter  →  '(module_name : "Renderer") AND "VirtualTexture"'

    Each result includes file, line, and optionally block QN + block_type.
    For full code, use read_symbol with the block QN, or read_file_range with file+line.
    db: database alias (from list_databases). Default: primary database.
    """
    conn = _get_conn(db)
    return db_search_fts(conn, keyword, path_filter, expand_item=expand_item, raw_query=raw_query)


@mcp.tool()
def read_file_range(
    file_path: str,
    start_line: int,
    end_line: int,
    view: str = "full",
    expand_item: list[str] | None = None,
    db: str = "",
) -> dict[str, Any]:
    """Read source code by file path and line range.

    Use when search_fts returns a location but read_symbol cannot resolve it,
    or when reading code outside symbol boundaries.

    view: "full" = complete code, "signature" = summary, "meta" = symbols only.

    Returns dict with {file, range, code?, symbols?} or {error, file}.
    db: database alias (from list_databases). Default: primary database.
    """
    conn = _get_conn(db)
    entry = db_read_file_range(conn, file_path, start_line, end_line, view=view, expand_item=expand_item)
    if not entry:
        return {"error": "not_found", "file": file_path}
    return entry


@mcp.tool()
def get_directory_structure(db: str = "") -> dict[str, Any]:
    """Get the directory structure summary from the indexed database.

    Returns total files, total modules, and module breakdown.
    Use module names as path_filter in search_fts_tool.
    db: database alias (from list_databases). Default: primary database.
    """
    conn = _get_conn(db)
    return db_get_directory_structure(conn)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
