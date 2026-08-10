#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON_BIN="$SCRIPT_DIR/../02-coreml-latencia/.venv/bin/python"

if [ ! -x "$PYTHON_BIN" ]; then
  echo "Python environment not found: $PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" "$SCRIPT_DIR/prepare_plue.py"
"$PYTHON_BIN" "$SCRIPT_DIR/train_plue.py" "$@"
