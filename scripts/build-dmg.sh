#!/bin/zsh
# Builds Dad Flow.app and packages it into dist/DadFlow.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Dad Flow"
DIST="dist"
APP="$DIST/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

echo "==> Building (release, Apple Silicon)"
swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DadFlow" "$APP/Contents/MacOS/DadFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
# SwiftPM resource bundles (e.g. from dependencies)
for b in "$BIN_DIR"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done

echo "==> Icon"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
# Pin the designated requirement to the bundle ID. A plain ad-hoc signature is tied to
# the exact build hash, so macOS would forget the Mic/Accessibility permissions after
# every rebuild or update.
codesign --force --deep --sign - --timestamp=none \
  --requirements '=designated => identifier "com.dadflow.app"' "$APP"
codesign --verify --deep --strict "$APP"
# Nudge Finder to drop any cached (blank) icon from a previous build.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "==> DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/READ ME FIRST.txt" <<TXT
Installing Dad Flow
===================
1. Drag "Dad Flow" onto the Applications folder.
2. Open Applications and double-click Dad Flow.
3. macOS will say it can't verify the developer (it isn't from the App Store).
   Click "Done", then open  System Settings -> Privacy & Security,
   scroll down and click "Open Anyway" next to Dad Flow. You only do this once.
4. Follow the friendly setup window.

Everything runs on your Mac. Nothing you say is ever sent anywhere.
TXT
rm -f "$DIST/DadFlow.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/DadFlow.dmg" >/dev/null
rm -rf "$STAGE"
echo "==> Done: $DIST/DadFlow.dmg (version $VERSION)"
