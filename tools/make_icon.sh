#!/usr/bin/env bash
# Generates Resources/AppIcon.icns from Resources/AppIcon.svg
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
swift - "$PWD/Resources/AppIcon.svg" "$tmp/icon_1024.png" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
guard let img = NSImage(contentsOfFile: a[1]) else { fatalError("could not read the SVG") }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
SWIFT
set_dir="$tmp/AppIcon.iconset"; mkdir "$set_dir"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon_1024.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$tmp/icon_1024.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
cp "$tmp/icon_1024.png" Resources/AppIcon-preview.png
rm -rf "$tmp"
echo "Generated Resources/AppIcon.icns"
