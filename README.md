# code-explore-by-sql

Local stdio MCP server for fast source code navigation using **SQLite FTS5** (trigram tokenizer) + **bracket skeleton indexing**.

## Features

- **Full-text search**: FTS5 with trigram tokenizer for code-symbol-precise search (`GetGBuffer`, `FMaterial`, `UE_LOG`)
- **Symbol lookup**: read code by qualified name with fuzzy matching (`Jump` → `ACharacter::Jump`)
- **Bracket skeleton index**: lightweight structural indexing via FSM brace matching (no AST parser needed)
- **12 language support**: C, C++, C#, Go, HLSL, GLSL, Java, JavaScript, Kotlin, Python, Rust, Swift
- **Multi-database**: query multiple codebases simultaneously via `CODE_SOURCE_DBS`
- **Token-efficient responses**: compact snippets (~2,600 tokens/20 results, 95% reduction vs full file reads)

## Test Installation

### From PyPI (recommended)

```bash
# Run the MCP server directly (no clone needed)
uvx code-explore-by-sql

# Or install persistently
pip install code-explore-by-sql
```

### Build a database

```bash
# Build index for your codebase
uvx code-explore-by-sql-build-db /path/to/source /path/to/output.db

# Smoke test with limited files
uvx code-explore-by-sql-build-db /path/to/source /path/to/output.db --limit 1000
```

Performance: ~84,700 files indexed in ~3.3 minutes on a 2-core machine.

## AI Agent UseCase
if use with AI Agent, copy current directory .claude/code-source-sql-search skill to AI Agent skills directory and modify mcp settings.

### Configure in MCP clients

**Claude Code** (`.claude/mcp.json`):
```json
{
  "mcpServers": {
    "code-source-sql": {
      "command": "uvx",
      "args": ["code-explore-by-sql"],
      "env": {
        "CODE_SOURCE_DB": "/path/to/your/code.db",
        "CODE_SOURCE_DBS": "/path/to/your/code.db:/path/to/another.db"
      }
    }
  }
}
```

**VS Code** (`.vscode/mcp.json`):
```json
{
  "servers": {
    "code-source-sql": {
      "type": "stdio",
      "command": "uvx",
      "args": ["code-explore-by-sql"],
      "env": {
        "CODE_SOURCE_DB": "/path/to/your/code.db"
      }
    }
  }
}
```

**OpenAI Codex** (`~/.codex/config.toml`):
```toml
[mcp_servers.code-source-sql]
command = "uvx"
args = ["code-explore-by-sql"]

[mcp_servers.code-source-sql.env]
CODE_SOURCE_DB = "/path/to/your/code.db"
```

**Hermes Agent** (`~/.hermes/config.yaml`):
```yaml
mcp_servers:
  code-source-sql:
    command: uvx
    args:
      - code-explore-by-sql
    env:
      CODE_SOURCE_DB: /path/to/your/code.db
```

## Tools (5)

| Tool | Purpose |
|------|---------|
| `list_databases` | Discover available databases with stats |
| `search_fts_tool` | FTS5 search — locate code blocks by keyword or raw FTS5 query |
| `read_symbol` | Read symbol code by qualified name (exact or fuzzy) |
| `read_file_range` | Read source code by file path and line range |
| `get_directory_structure` | Module/file counts overview |

### Multi-database

Each tool accepts an optional `db` parameter to select a database by alias. Aliases are derived from database filenames (`unreal.db` → `"unreal"`). Use `list_databases` to discover available aliases. 

### Search query modes

**Simple mode** (`keyword`):
```
keyword="GetGBuffer"
keyword="FMaterial Render"
```

**Advanced mode** (`raw_query`) — full FTS5 boolean:
```
raw_query='"GetGBuffer" AND "Emissive"'
raw_query='"Material" NOT "hlsl"'
raw_query='(file_path : "BasePass") AND "roughness"'
raw_query='(module_name : "Renderer") AND "VirtualTexture"'
```

### Three-level funnel

1. **`search_fts_tool(keyword)`** → file candidates + block QNs
2. **`search_fts_tool(raw_query, file_path filter)`** → precise block in target file
3. **`read_symbol(block QN)`** or **`read_file_range(file, line)`** → full code

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    MCP Server (FastMCP)                       │
├──────────┬──────────┬──────────┬──────────┬──────────────────┤
│ search   │ read     │ read     │ get_dir  │ list             │
│ fts_tool │ _symbol  │ _file    │ _struct  │ _databases       │
│          │          │ _range   │          │                  │
├──────────┴──────────┴──────────┴──────────┴──────────────────┤
│                     Query Pipeline                            │
│  FTS5 trigram → Symbol match → Edge extraction               │
├──────────────────────────────────────────────────────────────┤
│                    SQLite Database                            │
│  file_content + FTS5 │ symbol_index │ strict_edges           │
└──────────────────────────────────────────────────────────────┘
```

### Bracket skeleton index

A 6-state finite state machine (CODE, LINE_COMMENT, BLOCK_COMMENT, STRING, CHAR_LITERAL, RAW_STRING) scans source code tracking brace pairs while correctly ignoring braces in comments and strings.

Top-level blocks are classified by a **symbol analyzer** producing `block_type` (namespace/class/enum/function/macro) and `block_name` (qualified name).

### Multi-database registry

Databases are registered via environment variables at server startup:
- `CODE_SOURCE_DB` — primary database (default when `db` is omitted)
- `CODE_SOURCE_DBS` — colon-separated list of additional databases

Aliases are auto-derived from filename stems. Connections are cached with health checks.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `CODE_SOURCE_DB` | Yes | Path to primary SQLite database |
| `CODE_SOURCE_DBS` | No | Colon-separated paths to additional databases |

## Development

```bash
# Clone and setup
git clone https://github.com/didi514354875/code-explore-by-sql.git
cd code-explore-by-sql
uv sync --dev

# Run tests
uv run pytest
uv run ruff check .
```

## License

MIT

## References
Search inspiration from https://github.com/IOchair/SQL-ManyThing
