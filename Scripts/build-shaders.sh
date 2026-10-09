#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHADER_DIR="$PROJECT_DIR/.build/shaders"
mkdir -p "$SHADER_DIR"
xcrun -sdk macosx metal -std=metal3.2 -mmacosx-version-min=26.0 -c "$PROJECT_DIR/Sources/MajdataMac/MajdataShaders.metal" -o "$SHADER_DIR/Majdata.air"
xcrun -sdk macosx metallib "$SHADER_DIR/Majdata.air" -o "$PROJECT_DIR/Sources/MajdataMac/Resources/MajdataShaders.metallib"
