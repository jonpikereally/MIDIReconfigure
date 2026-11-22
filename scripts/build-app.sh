#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
project_root="$PWD"
dist="$project_root/dist"
app="$dist/MIDI Reconfigure.app"
info="$app/Contents/Info.plist"
swift_args=(--configuration release)
if [[ "${1:-}" == "--universal" ]]; then
    swift_args+=(--arch arm64 --arch x86_64)
    shift
fi
if [[ "$#" -gt 0 ]]; then
    printf '%s\n' 'Usage: scripts/build-app.sh [--universal]' >&2
    exit 64
fi

swift build "${swift_args[@]}"
binary_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
build_number="$(git rev-list --count HEAD 2>/dev/null || printf '1')"
build_number="${MIDI_BUILD_NUMBER:-$build_number}"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

icon_work="$(mktemp -d)"
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
swift Packaging/DrawIcon.swift "$iconset/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$iconset/icon_512x512@2x.png" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    if [[ "$size" != 512 ]]; then
        retina=$((size * 2))
        sips -z "$retina" "$retina" "$iconset/icon_512x512@2x.png" \
            --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil --convert icns "$iconset" --output "$app/Contents/Resources/AppIcon.icns"

cp Packaging/Info.plist "$info"
plutil -replace CFBundleVersion -string "$build_number" "$info"
plutil -replace MRCBuildDate -string "$build_date" "$info"
if [[ -n "${MIDI_VERSION:-}" ]]; then
    # Release builds take their version from the tag, e.g. v1.3.0.
    plutil -replace CFBundleShortVersionString -string "${MIDI_VERSION#v}" "$info"
fi
install -m 755 "$binary_dir/MIDIReconfigure" "$app/Contents/MacOS/MIDIReconfigure"
codesign --force --sign "${MIDI_SIGNING_IDENTITY:--}" --timestamp=none "$app"
codesign --verify --strict "$app"
rm -f "$dist/MIDI-Reconfigure.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/MIDI-Reconfigure.zip"
printf '\nApp: %s\nZIP: %s\n' "$app" "$dist/MIDI-Reconfigure.zip"
