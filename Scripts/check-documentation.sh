#!/bin/bash
#
# Checks every DocC catalog in this package. See CLAUDE.md.
#
# Deliberately does *not* use swift-docc-plugin. That would be a package dependency, and SwiftPM
# resolves manifest-level dependencies for every consumer whether they use them or not — this
# package has seven. Driving `docc` directly needs nothing beyond the toolchain.
#
# DocC reports dangling ``Symbol`` links and half-documented parameter lists as **warnings** and
# still exits 0, so nothing would stop you shipping a catalog that no longer resolves. This script
# treats any diagnostic as a failure.
#
# Usage:
#   Scripts/check-documentation.sh            incremental
#   Scripts/check-documentation.sh --clean    full rebuild, use after deleting a symbol

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

scratch=".build/documentation-build"
graphs=".build/symbol-graphs"

if [ "${1:-}" = "--clean" ]; then
    rm -rf "$scratch" "$graphs"
fi
mkdir -p "$graphs"

# SwiftPM 6.4's default build engine does not emit graphs reliably from -Xswiftc.
# Ask SwiftPM to extract every package target, including incrementally built modules.
echo "Building symbol graphs…"
build_log=$(mktemp)
if ! swift package --scratch-path "$scratch" --traits Vapor,Crypto,MCP dump-symbol-graph \
        --minimum-access-level public > "$build_log" 2>&1; then
    echo "✗ build failed"
    tail -20 "$build_log"
    rm -f "$build_log"
    exit 1
fi
graphs=$(sed -n 's/^Files written to //p' "$build_log" | tail -1)
rm -f "$build_log"
if [ ! -d "$graphs" ]; then
    echo "✗ SwiftPM did not report its symbol graph directory"
    exit 1
fi

# `xcrun` finds docc inside Xcode on macOS; Linux toolchains ship it on the PATH.
if command -v xcrun > /dev/null 2>&1; then
    docc="xcrun docc"
else
    docc="docc"
fi

status=0
found=0

for catalog in Sources/*/*.docc; do
    [ -d "$catalog" ] || continue
    found=1

    target=$(basename "$(dirname "$catalog")")

    # The build emits graphs for everything it compiled, dependencies included. Left together,
    # docc documents Vapor and NIO too and reports *their* doc-comment warnings as if they were
    # ours — so give each catalog a directory holding only its own module's graphs.
    target_graphs=".build/symbol-graphs-$target"
    rm -rf "$target_graphs"
    mkdir -p "$target_graphs"

    if ! compgen -G "$graphs/$target.symbols.json" > /dev/null; then
        echo "✗ $target — no symbol graph emitted; try --clean"
        status=1
        continue
    fi
    cp "$graphs/$target.symbols.json" "$target_graphs/"
    for extension_graph in "$graphs/$target@"*.symbols.json; do
        [ -e "$extension_graph" ] && cp "$extension_graph" "$target_graphs/"
    done

    output=".build/documentation/$target"
    rm -rf "$output"
    mkdir -p "$output"

    diagnostics=$($docc convert "$catalog" \
        --fallback-display-name "$target" \
        --fallback-bundle-identifier "com.funico.$target" \
        --additional-symbol-graph-dir "$target_graphs" \
        --output-path "$output" 2>&1 | grep -E "^(warning|error):" || true)

    if [ -n "$diagnostics" ]; then
        echo "✗ $target"
        echo "$diagnostics" | sed 's/^/    /'
        status=1
    else
        echo "✓ $target"
    fi
done

if [ "$found" -eq 0 ]; then
    echo "✗ no DocC catalogs found — every library target should have one"
    exit 1
fi

exit $status
