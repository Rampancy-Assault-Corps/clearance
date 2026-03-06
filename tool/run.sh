#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESTART_DELAY="${RESTART_DELAY:-2}"
RUN_ARGS=("$@")
HAS_CONFIG=0

for ARGUMENT in "${RUN_ARGS[@]}"; do
  if [[ "$ARGUMENT" == "--config" || "$ARGUMENT" == --config=* ]]; then
    HAS_CONFIG=1
    break
  fi
done

cd "$PROJECT_DIR"
if [[ "$HAS_CONFIG" -eq 0 ]]; then
  RUN_ARGS=(--config=config/bot.toml "${RUN_ARGS[@]}")
fi

while true; do
  if dart run bin/racbot_nyxx.dart "${RUN_ARGS[@]}"; then
    STATUS=0
  else
    STATUS=$?
  fi
  echo "[tool/run.sh] Process exited with status $STATUS. Restarting in $RESTART_DELAY seconds..."
  sleep "$RESTART_DELAY"
done
