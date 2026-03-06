#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/OutPut"
TARGET="exe"
COMPLETE=0
TARGET_OS=""
TARGET_ARCH=""

usage() {
  cat <<'EOF'
Usage: ./tool/compile.sh [--target exe|jit-snapshot|aot-snapshot|kernel] [--target-os OS] [--target-arch ARCH] [--output-dir PATH] [--complete]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --target-os)
      TARGET_OS="$2"
      shift 2
      ;;
    --target-arch)
      TARGET_ARCH="$2"
      shift 2
      ;;
    --complete)
      COMPLETE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

dart pub get

if [[ -n "$TARGET_OS" || -n "$TARGET_ARCH" ]]; then
  if [[ "$TARGET" != "exe" && "$TARGET" != "aot-snapshot" ]]; then
    echo "--target-os and --target-arch are only supported for exe and aot-snapshot." >&2
    exit 1
  fi
fi

SUFFIX=""
if [[ -n "$TARGET_OS" ]]; then
  SUFFIX="${SUFFIX}-${TARGET_OS}"
fi
if [[ -n "$TARGET_ARCH" ]]; then
  SUFFIX="${SUFFIX}-${TARGET_ARCH}"
fi

BASE_NAME="racbot_nyxx${SUFFIX}"
GENERATED_FILE="$OUTPUT_DIR/${BASE_NAME}.g.dart"
ARTIFACT_PATH=""

case "$TARGET" in
  exe)
    ARTIFACT_PATH="$OUTPUT_DIR/${BASE_NAME}"
    ;;
  jit-snapshot)
    ARTIFACT_PATH="$OUTPUT_DIR/${BASE_NAME}.jit"
    ;;
  aot-snapshot)
    ARTIFACT_PATH="$OUTPUT_DIR/${BASE_NAME}.aot"
    ;;
  kernel)
    ARTIFACT_PATH="$OUTPUT_DIR/${BASE_NAME}.dill"
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    usage >&2
    exit 1
    ;;
esac

rm -f "$OUTPUT_DIR"/racbot_nyxx* "$OUTPUT_DIR"/run.sh "$OUTPUT_DIR"/build-info.txt

GENERATE_ARGS=(--no-compile -o "$GENERATED_FILE")
if [[ "$COMPLETE" -eq 1 ]]; then
  GENERATE_ARGS+=(--complete)
fi

dart run nyxx_commands:compile "${GENERATE_ARGS[@]}" bin/racbot_nyxx.dart

COMPILE_ARGS=()
if [[ -n "$TARGET_OS" ]]; then
  COMPILE_ARGS+=(--target-os "$TARGET_OS")
fi
if [[ -n "$TARGET_ARCH" ]]; then
  COMPILE_ARGS+=(--target-arch "$TARGET_ARCH")
fi

dart compile "$TARGET" "${COMPILE_ARGS[@]}" "$GENERATED_FILE" -o "$ARTIFACT_PATH"

if [[ "$TARGET" == "exe" ]]; then
  chmod +x "$ARTIFACT_PATH"
fi

cat > "$OUTPUT_DIR/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="\$(cd "\$SCRIPT_DIR/.." && pwd)"
DEFAULT_CONFIG_PATH="\$SCRIPT_DIR/config/bot.toml"
if [[ ! -f "\$DEFAULT_CONFIG_PATH" && -f "\$PROJECT_DIR/config/bot.toml" && -d "\$PROJECT_DIR/bin" && -d "\$PROJECT_DIR/lib" ]]; then
  DEFAULT_CONFIG_PATH="\$PROJECT_DIR/config/bot.toml"
fi
RESTART_DELAY="\${RESTART_DELAY:-2}"
TARGET="$TARGET"
ARTIFACT_NAME="$(basename "$ARTIFACT_PATH")"

if [[ ! -f "\$SCRIPT_DIR/\$ARTIFACT_NAME" ]]; then
  echo "Missing compiled artifact: \$SCRIPT_DIR/\$ARTIFACT_NAME" >&2
  exit 1
fi

resolve_dartaotruntime() {
  if command -v dartaotruntime >/dev/null 2>&1; then
    command -v dartaotruntime
    return 0
  fi

  DART_BIN="\$(command -v dart || true)"
  if [[ -z "\$DART_BIN" ]]; then
    return 1
  fi

  CANDIDATE_ONE="\$(dirname "\$DART_BIN")/dartaotruntime"
  if [[ -x "\$CANDIDATE_ONE" ]]; then
    echo "\$CANDIDATE_ONE"
    return 0
  fi

  CANDIDATE_TWO="\$(dirname "\$DART_BIN")/cache/dart-sdk/bin/dartaotruntime"
  if [[ -x "\$CANDIDATE_TWO" ]]; then
    echo "\$CANDIDATE_TWO"
    return 0
  fi

  return 1
}

RUN_ARGS=("\$@")
HAS_CONFIG=0
for ARGUMENT in "\${RUN_ARGS[@]}"; do
  if [[ "\$ARGUMENT" == "--config" || "\$ARGUMENT" == --config=* ]]; then
    HAS_CONFIG=1
    break
  fi
done

if [[ "\$HAS_CONFIG" -eq 0 ]]; then
  RUN_ARGS=(--config="\$DEFAULT_CONFIG_PATH" "\${RUN_ARGS[@]}")
fi

while true; do
  if case "\$TARGET" in
    exe)
      "\$SCRIPT_DIR/\$ARTIFACT_NAME" "\${RUN_ARGS[@]}"
      ;;
    jit-snapshot|kernel)
      dart run "\$SCRIPT_DIR/\$ARTIFACT_NAME" "\${RUN_ARGS[@]}"
      ;;
    aot-snapshot)
      DARTAOT_RUNTIME="\$(resolve_dartaotruntime || true)"
      if [[ -z "\$DARTAOT_RUNTIME" ]]; then
        echo "Unable to find dartaotruntime for \$ARTIFACT_NAME" >&2
        exit 1
      fi
      "\$DARTAOT_RUNTIME" "\$SCRIPT_DIR/\$ARTIFACT_NAME" "\${RUN_ARGS[@]}"
      ;;
    *)
      echo "Unsupported run target: \$TARGET" >&2
      exit 1
      ;;
  esac
  then
    STATUS=0
  else
    STATUS=\$?
  fi

  echo "[run.sh] Process exited with status \$STATUS. Restarting in \$RESTART_DELAY seconds..."
  sleep "\$RESTART_DELAY"
done
EOF

chmod +x "$OUTPUT_DIR/run.sh"

cat > "$OUTPUT_DIR/build-info.txt" <<EOF
target=$TARGET
artifact=$(basename "$ARTIFACT_PATH")
generated=$(basename "$GENERATED_FILE")
target_os=$TARGET_OS
target_arch=$TARGET_ARCH
run_script=run.sh
EOF

echo "Built $TARGET artifact at $ARTIFACT_PATH"
echo "Auto-restart runner written to $OUTPUT_DIR/run.sh"
