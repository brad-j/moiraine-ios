#!/bin/sh
# The UI tests against gaidin's faux server: starts scripts/dev-faux.ts on a port of its own, runs MoiraineUITests on a
# simulator, and stops the server. Needs gaidin checked out beside this directory, with its dependencies installed.
# DESTINATION overrides the simulator ('platform=iOS Simulator,name=iPhone 17' by default).
set -eu
cd "$(dirname "$0")/.."
PORT="${PORT:-8421}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
LOG="$(mktemp -t moiraine-e2e)"
PORT="$PORT" node --no-warnings scripts/dev-faux.ts >"$LOG" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 50); do
	grep -q "gaidin (faux) at" "$LOG" && break
	sleep 0.2
done
grep -q "gaidin (faux) at" "$LOG" || { cat "$LOG"; exit 1; }
xcodegen generate --quiet
TEST_RUNNER_MOIRAINE_SERVER="http://127.0.0.1:$PORT" xcodebuild test \
	-project Moiraine.xcodeproj -scheme Moiraine \
	-destination "$DESTINATION" \
	-derivedDataPath build/DerivedData \
	-only-testing:MoiraineUITests \
	"$@"
