#!/usr/bin/env bash
# Compila "AEM Conest.app" (universal arm64 + x86_64) y genera un .dmg.
#
# Sin firmar (por defecto):   ./build.sh
# Firmada y notarizada:       SIGN_IDENTITY="Developer ID Application: Tu Nombre (TEAMID)" \
#                             NOTARY_PROFILE="mi-perfil-notarytool" ./build.sh
#   (el perfil se crea una vez con: xcrun notarytool store-credentials mi-perfil-notarytool)
set -eu
cd "$(dirname "$0")"

APP_NAME="AEM Conest"
BUNDLE_ID="com.aemconest.app"
VERSION="1.0"
OUT="dist"
APP="$OUT/$APP_NAME.app"

tools/gen_defaults.sh
swift build -c release --arch arm64 --arch x86_64

rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/out/Products/Release/CDNFiltering" "$APP/Contents/MacOS/CDNFiltering"

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
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"   # firma ad-hoc: la app arranca, pero Gatekeeper pedirá "Abrir igualmente"
fi

DMG="$OUT/AEM-Conest-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Listo: $APP"
echo "       $DMG"
