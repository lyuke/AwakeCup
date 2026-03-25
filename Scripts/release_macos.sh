#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AwakeCup"
APP_BUNDLE_ID="com.awakecup.app"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_STAGING_DIR="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

SWIFT_BUILD_CONFIG="release"
BUILD_DIR="$ROOT_DIR/.build/$SWIFT_BUILD_CONFIG"
BIN_PATH="$BUILD_DIR/$APP_NAME"

echo "[1/4] SwiftPM build ($SWIFT_BUILD_CONFIG)"
swift build -c "$SWIFT_BUILD_CONFIG" --package-path "$ROOT_DIR"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "error: binary not found at $BIN_PATH" 1>&2
  exit 1
fi

echo "[2/4] Create .app bundle"
rm -rf "$APP_DIR" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>AwakeCup</string>
  <key>CFBundleIdentifier</key>
  <string>com.awakecup.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AwakeCup</string>
  <key>CFBundleDisplayName</key>
  <string>AwakeCup</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "[3/4] Code sign (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "[4/4] Build DMG"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "done: $DMG_PATH"
