#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p GlassCue.app/Contents/MacOS GlassCue.app/Contents/Resources
swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -module-cache-path "${TMPDIR:-/tmp}/glasscue-swift-cache" Source/*.swift -o GlassCue.app/Contents/MacOS/GlassCue -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Carbon
cp Info.plist GlassCue.app/Contents/Info.plist
if [[ -f GlassCue.icns ]]; then cp GlassCue.icns GlassCue.app/Contents/Resources/GlassCue.icns; fi
codesign --force --sign - GlassCue.app
echo "Built GlassCue.app"
