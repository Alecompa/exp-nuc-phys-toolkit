#!/bin/zsh
# Runs the NucPhysKit test suite (Swift Testing) on macOS. Needs Xcode (not only the Command Line Tools).
set -euo pipefail
cd "${0:A:h}/../Packages/NucToolkit"
swift test "$@"
