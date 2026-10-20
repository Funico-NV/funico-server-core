#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
awk '/^```swift$/ { example = 1; next } example && /^```$/ { exit } example { print }' README.md > .build/readme-demo.swift
diff -u Sources/MCPDemo/main.swift .build/readme-demo.swift
swift package dump-symbol-graph --minimum-access-level public > .build/documentation-symbols.log 2>&1
mkdir -p .build/documentation-symbols
graph=$(find .build -path '*/symbolgraph/FunicoMCPTooling.symbols.json' -print -quit)
[ -n "$graph" ] || { echo 'No module symbol graph found' >&2; exit 1; }
cp "$graph" .build/documentation-symbols/
if command -v xcrun >/dev/null 2>&1; then docc=(xcrun docc); else docc=(docc); fi
"${docc[@]}" convert Sources/FunicoMCPTooling/FunicoMCPTooling.docc \
    --fallback-display-name FunicoMCPTooling --fallback-bundle-identifier be.funico.mcp-tooling \
    --additional-symbol-graph-dir .build/documentation-symbols \
    --output-path .build/documentation > .build/documentation.log 2>&1
if grep -E '(^|[[:space:]])(warning|error):' .build/documentation.log; then exit 1; fi
echo 'README example and FunicoMCPTooling DocC passed.'
