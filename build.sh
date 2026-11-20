#!/usr/bin/env bash
# Builds "AEM Conest.app" (universal arm64 + x86_64) and creates a .dmg.
#
# Unsigned (default):         ./build.sh
# Signed and notarized:       SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#                             NOTARY_PROFILE="my-notarytool-profile" ./build.sh
#   (create the profile once with: xcrun notarytool store-credentials my-notarytool-profile)
set -eu
cd "$(dirname "$0")"

APP_NAME="AEM Conest"
BUNDLE_ID="com.aemconest.app"
VERSION="$(tr -d '[:space:]' < VERSION)"   # CalVer YYYY.MM.DD, single source: ./VERSION
OUT="dist"
APP="$OUT/$APP_NAME.app"

tools/gen_defaults.sh
swift build -c release --arch arm64 --arch x86_64
# The products folder depends on the toolchain (.build/out/… or .build/apple/…), so ask SwiftPM.
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CDNFiltering"

rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CDNFiltering"

[ -f Resources/AppIcon.icns ] || tools/make_icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>CDNFiltering</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"   # ad-hoc signature: the app launches, but Gatekeeper will ask for "Open Anyway"
fi

DMG="$OUT/AEM-Conest-$VERSION.dmg"
# `hdiutil create -srcfolder` fails with "Resource busy" on recent macOS (seen on 26.5), so build
# the image by hand: blank read-write image -> mount -> copy -> unmount -> compress to UDZO.
WORK="$(mktemp -d)"
RW="$WORK/rw.dmg"
MNT="$WORK/mnt"
SIZE_MB=$(( $(du -sm "$APP" | cut -f1) + 20 ))
hdiutil create -size "${SIZE_MB}m" -fs HFS+ -volname "$APP_NAME" -ov "$RW" >/dev/null
hdiutil attach "$RW" -nobrowse -noautoopen -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" -force >/dev/null 2>&1 || true' EXIT
ditto "$APP" "$MNT/$APP_NAME.app"
ln -s /Applications "$MNT/Applications"
hdiutil detach "$MNT" >/dev/null
trap - EXIT
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" >/dev/null
rm -rf "${WORK:?}"

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Done: $APP"
echo "      $DMG"
