#!/bin/zsh
# Builds Release and replaces /Applications/MacRaindrop.app, relaunching it if it was open.
set -euo pipefail
cd "${0:A:h}/.."

xcodebuild -project MacRaindrop.xcodeproj -scheme MacRaindrop -configuration Release \
    -derivedDataPath build -quiet build

installed=/Applications/MacRaindrop.app
was_running=false
if pgrep -f "^$installed/" >/dev/null; then
    was_running=true
    osascript -e "tell application \"$installed\" to quit"
    while pgrep -f "^$installed/" >/dev/null; do sleep 0.2; done
fi

rm -rf "$installed"
cp -R build/Build/Products/Release/MacRaindrop.app "$installed"
echo "Installed $installed"
if $was_running; then open "$installed"; fi
