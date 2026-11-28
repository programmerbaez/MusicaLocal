#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
swiftc -O -target "$(uname -m)-apple-macos12.0" -module-cache-path "$WORK/modules" \
    "$ROOT/src/Services/MetadataWriter.swift" "$ROOT/src/Services/ID3Metadata.swift" \
    "$ROOT/src/Services/M4AMetadata.swift" "$ROOT/src/Services/MetadataRecognition.swift" \
    "$ROOT/tests/MetadataChecks.swift" -o "$WORK/check"
"$WORK/check" "$WORK" "${MUSICALOCAL_CHROMAPRINT_DIR:-}"
