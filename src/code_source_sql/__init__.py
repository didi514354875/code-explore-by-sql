"""UE Semantic Search — plan.md implementation.

Three-table architecture:
  file_content (FTS5) -> symbol_index (QN + UE meta) -> strict_edges (4 types)
"""

from .server import main

__all__ = ["main"]
