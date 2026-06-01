"""Entry shim: adds code-source-sql directory to sys.path and delegates to server.main()."""
import sys
from pathlib import Path

_pkg = Path(__file__).parent.parent / "code-source-sql"
sys.path.insert(0, str(_pkg))

from server import main as _main  # noqa: E402


def main() -> None:
    _main()
