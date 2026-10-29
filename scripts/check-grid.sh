#!/bin/zsh
# Runs the AppKit collection checks against disposable sample data, without touching the user's library.
set -euo pipefail
cd "${0:A:h}/.."
check_dir=$(mktemp -d /private/tmp/macraindrop-grid-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
check_app="$check_dir/GridCheck.app"
mkdir -p "$check_app/Contents/MacOS" "$check_app/Contents/Resources"
cp MacRaindrop/SampleData/*.json "$check_app/Contents/Resources/"
cat > "$check_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.macraindrop.gridcheck</string>
<key>CFBundleExecutable</key><string>GridCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
sources=("${(@f)$(rg --files MacRaindrop -g '*.swift' | rg -v '/MyApp.swift$')}")
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -target "$(uname -m)-apple-macos27.2" -o "$check_app/Contents/MacOS/GridCheck" \
    "${sources[@]}" scripts/check-grid.swift
"$check_app/Contents/MacOS/GridCheck"
