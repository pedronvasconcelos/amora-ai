#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
    printf 'package: %s\n' "$1" >&2
    exit 1
}

ok() {
    printf 'ok: %s\n' "$1"
}

[ "$(uname -s)" = Darwin ] || fail "packaging requires macOS"
[ -f assets/icon.png ] || fail "assets/icon.png is missing"

version=${AMORA_VERSION:-0.1.0}
version=${version#v}
case "$version" in
    *[0-9]*) ;;
    *) fail "AMORA_VERSION must contain a number" ;;
esac

app="$root/dist/Amora.app"
dmg="$root/dist/Amora-${version}-arm64.dmg"
work=$(mktemp -d)
mount=""

cleanup() {
    if [ -n "$mount" ] && [ -d "$mount" ]; then
        hdiutil detach "$mount" -quiet 2>/dev/null || hdiutil detach "$mount" -force -quiet 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

printf 'package: building arm64 release %s\n' "$version"
swift build -c release --arch arm64
bin=$(swift build -c release --arch arm64 --show-bin-path)
[ -x "$bin/Amora" ] || fail "release executable was not built"
[ -f "$bin/Amora_Amora.bundle/codex-hook.sh" ] || fail "bundled hook scripts were not built"

rm -rf "$root/dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

ditto "$bin/Amora" "$app/Contents/MacOS/Amora"
ditto "$bin/Amora_Amora.bundle/claude-hook.sh" "$app/Contents/Resources/claude-hook.sh"
ditto "$bin/Amora_Amora.bundle/codex-hook.sh" "$app/Contents/Resources/codex-hook.sh"
ditto "$bin/Amora_Amora.bundle/cursor-hook.sh" "$app/Contents/Resources/cursor-hook.sh"
chmod 755 "$app/Contents/MacOS/Amora" \
    "$app/Contents/Resources/claude-hook.sh" \
    "$app/Contents/Resources/codex-hook.sh" \
    "$app/Contents/Resources/cursor-hook.sh"

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
sips -z 16 16 assets/icon.png --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 assets/icon.png --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 assets/icon.png --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 assets/icon.png --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 assets/icon.png --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 assets/icon.png --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 assets/icon.png --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 assets/icon.png --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 assets/icon.png --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 assets/icon.png --out "$iconset/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

printf '%s' 'APPL????' > "$app/Contents/PkgInfo"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Amora</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>ai.amora.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Amora</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
	<key>CFBundleVersion</key>
	<string>$version</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Amora shows your upcoming events from Google and other calendars in the menu and has your pets wave before a meeting starts.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>Amora shows your upcoming events from Google and other calendars in the menu and has your pets wave before a meeting starts.</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

executable="$app/Contents/MacOS/Amora"
otool -l "$executable" | awk '/cmd LC_RPATH/{f=1} f && /path /{print $2; f=0}' | while IFS= read -r rpath; do
    case "$rpath" in
        *Xcode.app*|*CommandLineTools*)
            install_name_tool -delete_rpath "$rpath" "$executable"
            ;;
    esac
done

codesign --force --sign - --identifier ai.amora.app --timestamp=none "$app" >/dev/null 2>&1
xattr -cr "$app" 2>/dev/null || true

stage="$work/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Amora.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Amora -srcfolder "$stage" -ov -format UDZO -fs HFS+ "$dmg" >/dev/null

plutil -lint "$app/Contents/Info.plist" >/dev/null || fail "Info.plist is invalid"
[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" = ai.amora.app ] || fail "bundle identifier is wrong"
[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" = AppIcon ] || fail "app icon is not configured"
[ "$(plutil -extract LSUIElement raw "$app/Contents/Info.plist")" = true ] || fail "LSUIElement must be true"
plutil -extract NSCalendarsFullAccessUsageDescription raw "$app/Contents/Info.plist" >/dev/null || fail "calendar usage description is missing"
[ -f "$app/Contents/Resources/AppIcon.icns" ] || fail "AppIcon.icns is missing"
[ -x "$app/Contents/Resources/codex-hook.sh" ] || fail "codex hook is missing"
[ -x "$app/Contents/Resources/cursor-hook.sh" ] || fail "cursor hook is missing"
[ -x "$app/Contents/Resources/claude-hook.sh" ] || fail "claude hook is missing"
[ "$(lipo -archs "$executable")" = arm64 ] || fail "executable must be arm64 only"
otool -L "$executable" | grep -E '/Applications/Xcode.app|/Library/Developer/CommandLineTools' >/dev/null && fail "executable links toolchain libraries"
otool -l "$executable" | awk '/cmd LC_RPATH/{f=1} f && /path /{print $2; f=0}' | grep -E 'Xcode.app|CommandLineTools' >/dev/null && fail "executable still has a toolchain rpath"
codesign --verify "$app" || fail "ad-hoc signature is invalid"
[ -s "$dmg" ] || fail "disk image was not created"

mount="$work/mnt"
mkdir -p "$mount"
hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg" >/dev/null
[ -x "$mount/Amora.app/Contents/MacOS/Amora" ] || fail "disk image is missing Amora.app"
[ -L "$mount/Applications" ] || fail "disk image is missing the Applications shortcut"
[ -f "$mount/Amora.app/Contents/Resources/AppIcon.icns" ] || fail "disk image app is missing its icon"
[ -x "$mount/Amora.app/Contents/Resources/codex-hook.sh" ] || fail "disk image app is missing hook resources"
hdiutil detach "$mount" -quiet
mount=""

ok "Amora.app"
ok "$dmg"
printf 'package: %s\n' "$app"
printf 'package: %s\n' "$dmg"
