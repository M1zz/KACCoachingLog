#!/bin/bash
# Verifies the project on a Mac with Xcode installed.
#   ./Scripts/verify.sh          # core checks + macOS build + iOS Simulator build
#   ./Scripts/verify.sh core     # core checks only
set -uo pipefail
cd "$(dirname "$0")/.."
LOG_DIR="Scripts/output"
mkdir -p "$LOG_DIR"
status=0

echo "== Core checks (validation + XLSX export) =="
if xcrun swiftc -O -o "$LOG_DIR/kac-core-tests" \
    KACCoachingLog/Core/*.swift KACCoachingLog/Export/*.swift Scripts/CoreTests/main.swift \
    > "$LOG_DIR/core-build.log" 2>&1; then
  "$LOG_DIR/kac-core-tests" "$LOG_DIR" | tee "$LOG_DIR/core-tests.log" || status=1
else
  echo "Core build failed:"; cat "$LOG_DIR/core-build.log"; status=1
fi

if [ "${1:-all}" = "core" ]; then exit $status; fi

build() {
  local name="$1"; shift
  echo "== Build: $name =="
  if xcodebuild -project KACCoachingLog.xcodeproj -scheme KACCoachingLog -configuration Debug \
      -derivedDataPath "$LOG_DIR/DerivedData" CODE_SIGNING_ALLOWED=NO "$@" build \
      > "$LOG_DIR/build-$name.log" 2>&1; then
    echo "   OK"
  else
    echo "   FAILED — errors:"
    grep -E "error:|BUILD FAILED" "$LOG_DIR/build-$name.log" | sort -u | head -40
    status=1
  fi
  grep -c "warning:" "$LOG_DIR/build-$name.log" | xargs echo "   warnings:"
}

build macOS -destination "generic/platform=macOS"
build iOS -destination "generic/platform=iOS Simulator"

echo
[ $status -eq 0 ] && echo "VERIFY PASSED" || echo "VERIFY FAILED (logs in $LOG_DIR)"
exit $status
