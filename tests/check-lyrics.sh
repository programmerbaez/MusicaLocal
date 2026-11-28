#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
SOURCES=()
while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(find "$ROOT/src" -type f -name '*.swift' -print0)
swiftc -target "$(uname -m)-apple-macos12.0" -module-cache-path "$WORK/modules" \
    -I "$ROOT/src/Services/AudioAtomics" "${SOURCES[@]}" "$ROOT/tests/LyricsChecks.swift" -o "$WORK/check"
"$WORK/check" "$WORK"
