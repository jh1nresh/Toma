#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

PYTHON=${CODEX_BUNDLED_PYTHON:-/Users/jhinresh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3}
PET_VALIDATOR=${HATCH_PET_VALIDATOR:-/Users/jhinresh/.codex/skills/hatch-pet/scripts/validate_atlas.py}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/TomaDerivedData}
PRIVATE_ATLAS=Toma/Resources/pet-sprites.png

test -x "$PYTHON"

if [ -z "${DESTINATION:-}" ]; then
  simulator_udid=$(xcrun simctl list devices available -j | "$PYTHON" -c '
import json, sys
devices = [
    device
    for runtime in json.load(sys.stdin)["devices"].values()
    for device in runtime
    if "iPhone" in device.get("deviceTypeIdentifier", "")
]
booted = [device for device in devices if device.get("state") == "Booted"]
choices = booted or devices
print(choices[0]["udid"] if choices else "")
')
  test -n "$simulator_udid"
  DESTINATION="platform=iOS Simulator,id=$simulator_udid"
fi

mkdir -p .tmp

plutil -lint Toma/Info.plist

if [ -f "$PRIVATE_ATLAS" ]; then
  test -f "$PET_VALIDATOR"
  "$PYTHON" "$PET_VALIDATOR" \
    "$PRIVATE_ATLAS" \
    --require-v2 \
    --json-out .tmp/atlas-validation.json
else
  rm -f .tmp/atlas-validation.json
  echo "Private pet sprite not present; testing the built-in fallback."
fi

intent_count=$(rg ': AppIntent' Toma --glob '*.swift' | wc -l | tr -d ' ')
expected_intent_count=$(rg -c '^struct (AskPetIntent|PrepareTomorrowIntent|ContinuePendingTaskIntent): AppIntent' Toma/App/TomaIntents.swift)
shortcut_count=$(rg -c '^[[:space:]]*AppShortcut\(' Toma/App/TomaIntents.swift)
test "$intent_count" -eq 3
test "$expected_intent_count" -eq 3
test "$shortcut_count" -eq 3

if rg -n --hidden \
  '(sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' \
  Toma TomaTests TomaUITests docs; then
  echo "Potential embedded secret found" >&2
  exit 1
fi

ruby scripts/generate_project.rb

simulator_udid=$(printf '%s\n' "$DESTINATION" | sed -n 's/.*id=\([^,]*\).*/\1/p')
if [ -n "$simulator_udid" ]; then
  xcrun simctl boot "$simulator_udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_udid" -b
  xcrun simctl uninstall "$simulator_udid" io.jeezlabs.toma >/dev/null 2>&1 || true
fi

xcodebuild \
  -project Toma.xcodeproj \
  -scheme Toma \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test
