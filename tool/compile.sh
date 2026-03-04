#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"
mkdir -p build

dart pub get
dart run nyxx_commands:compile -o build/racbot_nyxx.g.dart bin/racbot_nyxx.dart
mv build/racbot_nyxx.g.exe build/racbot_nyxx
chmod +x build/racbot_nyxx
