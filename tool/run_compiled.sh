#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_RUNNER="$PROJECT_DIR/OutPut/run.sh"

if [[ ! -x "$OUTPUT_RUNNER" ]]; then
  echo "Missing compiled runner: $OUTPUT_RUNNER" >&2
  echo "Run ./tool/compile.sh first." >&2
  exit 1
fi

exec "$OUTPUT_RUNNER" "$@"
