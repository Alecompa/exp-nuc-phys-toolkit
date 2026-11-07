#!/bin/zsh
# Type-checks ToolkitUI against the macOS SDK (iOS-only modifiers are wrapped in #if os(iOS)).
# Needs the NucPhysKit module built by Tools/test.sh.
set -euo pipefail
cd "${0:A:h}/../Packages/NucToolkit"
B=.build-swiftc
[[ -f $B/NucPhysKit.swiftmodule ]] || ../../Tools/test.sh >/dev/null
swiftc -swift-version 6 -parse-as-library -typecheck -target arm64-apple-macosx26.0 -I $B \
  $(find Sources/ToolkitUI -name '*.swift')
echo "ToolkitUI type-checks (macOS SDK)."
