#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
testDirectory=$(mktemp -d "${TMPDIR:-/tmp}/MacThermal-tests.XXXXXX")
trap 'rm -rf "$testDirectory"' EXIT
xcrun clang -I Sources Tests/FanAssistTests.c -o "$testDirectory/FanAssistTests"
"$testDirectory/FanAssistTests"
xcrun clang -mmacosx-version-min=12.0 -c Sources/SMC.c -o "$testDirectory/SMC.o"
xcrun swiftc -swift-version 5 -Onone -target x86_64-apple-macosx12.0 -import-objc-header Sources/SMC.h Sources/main.swift Sources/ThermalModel.swift "$testDirectory/SMC.o" -framework AppKit -framework IOKit -framework Metal -o "$testDirectory/MacThermalTests"
"$testDirectory/MacThermalTests" --self-test
