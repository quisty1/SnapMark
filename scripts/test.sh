#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--native-only" ]]; then swift run SnapMarkTests; fi
swift build --product SnapMark
BIN="$(swift build --show-bin-path)"
SOURCES=()
for SOURCE in Sources/SnapMark/*.swift; do
    if [[ "$SOURCE" != */main.swift ]]; then SOURCES+=("$SOURCE"); fi
done
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -I "$BIN/Modules" \
    "${SOURCES[@]}" Tests/NativeChecks/NativeChecks.swift "$BIN"/SnapMarkCore.build/*.swift.o \
    -o "$BIN/SnapMarkNativeChecks"
"$BIN/SnapMarkNativeChecks"
