#!/bin/bash
# Збирає build/DiskHealth.app (universal: arm64 + x86_64) з вбудованим smartctl,
# а з --dmg ще й build/DiskHealth-<версія>.dmg.
# Використання: scripts/build-app.sh [--smartctl /шлях/до/smartctl] [--dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

SMARTCTL=""
MAKE_DMG=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --smartctl) SMARTCTL="$2"; shift 2 ;;
        --dmg) MAKE_DMG=1; shift ;;
        *) echo "Невідомий аргумент: $1" >&2; exit 64 ;;
    esac
done

# smartctl: явно заданий → зібраний scripts/build-smartctl.sh → встановлений через brew.
if [[ -z "$SMARTCTL" ]]; then
    if [[ -x vendor/smartctl ]]; then
        SMARTCTL=vendor/smartctl
    elif command -v brew >/dev/null && brew --prefix smartmontools >/dev/null 2>&1; then
        SMARTCTL="$(brew --prefix smartmontools)/bin/smartctl"
    else
        SMARTCTL="$(command -v smartctl || true)"
    fi
fi
if [[ -z "$SMARTCTL" || ! -x "$SMARTCTL" ]]; then
    echo "smartctl не знайдено. Запустіть scripts/build-smartctl.sh або передайте --smartctl ШЛЯХ" >&2
    exit 1
fi
SMARTCTL="$(realpath "$SMARTCTL")"
if ! lipo -archs "$SMARTCTL" | grep -qw arm64 || ! lipo -archs "$SMARTCTL" | grep -qw x86_64; then
    echo "Увага: $SMARTCTL не universal ($(lipo -archs "$SMARTCTL")) — запустіть scripts/build-smartctl.sh" >&2
fi

# Окремі збірки під кожну архітектуру: мультиархітектурний swift build потребує Xcode.
BINS=()
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0" --product DiskHealth
    BINS+=(".build/$ARCH-apple-macosx/release/DiskHealth")
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP=build/DiskHealth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/DiskHealth"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$SMARTCTL" "$APP/Contents/Resources/smartctl"
chmod 755 "$APP/Contents/Resources/smartctl"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
[[ -f vendor/smartmontools-COPYING ]] && cp vendor/smartmontools-COPYING "$APP/Contents/Resources/"

# Ad-hoc підпис: без сертифіката Apple Developer інший немає.
codesign --force -s - "$APP/Contents/Resources/smartctl"
codesign --force -s - "$APP"

echo "Готово: $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/DiskHealth"); smartctl: $(lipo -archs "$SMARTCTL"))"

if [[ $MAKE_DMG == 1 ]]; then
    DMG="build/DiskHealth-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -quiet -volname "DiskHealth $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
    echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
fi
