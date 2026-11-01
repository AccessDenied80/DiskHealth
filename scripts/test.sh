#!/bin/bash
# swift-testing без Xcode: Testing.framework лежить у CLT поза стандартним шляхом пошуку,
# а оверлей _Testing_Foundation у CLT без swiftmodule — тому вимикаємо cross-import overlays.
set -euo pipefail
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
cd "$(dirname "$0")/.."
swift test -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
