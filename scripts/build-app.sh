#!/bin/bash
# Збирає build/DiskHealth.app з вбудованим smartctl.
# Використання: scripts/build-app.sh [--smartctl /шлях/до/smartctl]
set -euo pipefail
cd "$(dirname "$0")/.."

SMARTCTL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --smartctl) SMARTCTL="$2"; shift 2 ;;
        *) echo "Невідомий аргумент: $1" >&2; exit 64 ;;
    esac
done

if [[ -z "$SMARTCTL" ]]; then
    if command -v brew >/dev/null && brew --prefix smartmontools >/dev/null 2>&1; then
        SMARTCTL="$(brew --prefix smartmontools)/bin/smartctl"
    else
        SMARTCTL="$(command -v smartctl || true)"
    fi
fi
if [[ -z "$SMARTCTL" || ! -x "$SMARTCTL" ]]; then
    echo "smartctl не знайдено. Встановіть: brew install smartmontools, або передайте --smartctl ШЛЯХ" >&2
    exit 1
fi
SMARTCTL="$(realpath "$SMARTCTL")"

ARCH="$(uname -m)"
if ! lipo -archs "$SMARTCTL" | grep -qw "$ARCH"; then
    echo "Увага: $SMARTCTL не містить архітектури $ARCH ($(lipo -archs "$SMARTCTL"))" >&2
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DiskHealth"

APP=build/DiskHealth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DiskHealth"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$SMARTCTL" "$APP/Contents/Resources/smartctl"
chmod 755 "$APP/Contents/Resources/smartctl"

# Ad-hoc підпис: достатньо для локального запуску.
codesign --force -s - "$APP/Contents/Resources/smartctl"
codesign --force -s - "$APP"

echo "Готово: $APP (smartctl: $SMARTCTL, $(lipo -archs "$SMARTCTL"))"
