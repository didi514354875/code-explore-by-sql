"""Allow running as: python src/code-source-sql/server.py"""
import sys
from pathlib import Path

# Add parent to sys.path so relative imports work
sys.path.insert(0, str(Path(__file__).parent))

from server import main

if __name__ == "__main__":
    main()
