#!/bin/bash
# Збирає universal (arm64 + x86_64) smartctl зі сирців smartmontools у vendor/smartctl.
# Використання: scripts/build-smartctl.sh [шлях/до/smartmontools-7.5.tar.gz]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=7.5
SHA256=690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e
URL="https://github.com/smartmontools/smartmontools/releases/download/RELEASE_${VERSION//./_}/smartmontools-$VERSION.tar.gz"
MIN_MACOS=13.0
SDK="$(xcrun --show-sdk-path)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TARBALL="${1:-}"
if [[ -z "$TARBALL" ]]; then
    TARBALL="$WORK/smartmontools-$VERSION.tar.gz"
    curl -fsSL -o "$TARBALL" "$URL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c -

for ARCH in arm64 x86_64; do
    SRC="$WORK/$ARCH"
    mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" --strip-components 1
    HOST=$([[ $ARCH == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
    (
        cd "$SRC"
        # Заголовки libc++ беремо з SDK: у деяких інсталяціях Command Line Tools
        # тека usr/include/c++/v1 тулчейну неповна, і clang++ не знаходить <string>.
        ./configure --host="$HOST" --quiet \
            CC="clang -arch $ARCH -mmacosx-version-min=$MIN_MACOS" \
            CXX="clang++ -arch $ARCH -mmacosx-version-min=$MIN_MACOS -nostdinc++ -isystem $SDK/usr/include/c++/v1" >/dev/null
        make -j"$(sysctl -n hw.ncpu)" smartctl >/dev/null
    )
done

mkdir -p vendor
lipo -create "$WORK/arm64/smartctl" "$WORK/x86_64/smartctl" -output vendor/smartctl
cp "$WORK/x86_64/COPYING" vendor/smartmontools-COPYING
echo "Готово: vendor/smartctl ($(lipo -archs vendor/smartctl)), smartmontools $VERSION"
