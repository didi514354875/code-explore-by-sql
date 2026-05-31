"""Pytest collection policy for local and integration tests."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

# These files are script-style diagnostics or Unreal DB integration tests.
# They require a large local unreal.db, can copy multi-GB files, or expose helper
# functions whose names start with test_ but are not pytest test cases.
_INTEGRATION_ONLY = {
    "test_benchmark.py",
    "test_block_index_data.py",
    "test_query_efficiency.py",
    "test_tools.py",
}


def pytest_ignore_collect(collection_path: Any, config: Any) -> bool:
    """Keep default `pytest` fast and hermetic.

    Set RUN_INTEGRATION_TESTS=1 to include local Unreal DB benchmarks and
    integration diagnostics.
    """
    if os.environ.get("RUN_INTEGRATION_TESTS") == "1":
        return False
    return Path(str(collection_path)).name in _INTEGRATION_ONLY
