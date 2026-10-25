#!/bin/bash
set -euo pipefail
TARGET="${1:?Runtime directory required}"
PYTHON="${2:?Python 3.10 or later required}"
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$PYTHON" "$HERE/install-runtime.py" "$TARGET"
