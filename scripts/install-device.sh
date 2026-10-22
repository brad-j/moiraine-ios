#!/bin/sh
# Builds a release of the app, signed with your Apple Development certificate, and installs it on a paired iPhone.
# TEAM is your team ID (from the certificate when not given); DEVICE is the phone's name or identifier, as
# `xcrun devicectl list devices` shows it (the only physical iPhone when not given). --build-only stops before
# installing. Nothing about your team or phone is written into the project.
set -eu
cd "$(dirname "$0")/.."
BUILD_ONLY=0
[ "${1:-}" = "--build-only" ] && BUILD_ONLY=1
if [ -z "${TEAM:-}" ]; then
	TEAM="$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
fi
[ -n "$TEAM" ] || { echo "No Apple Development certificate; set TEAM to your team ID." >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project Moiraine.xcodeproj -scheme Moiraine -configuration Release \
	-destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
	-allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build | grep -E 'error|warning: |BUILD' || true
APP="build/DerivedData/Build/Products/Release-iphoneos/Moiraine.app"
[ -d "$APP" ] || { echo "The build failed." >&2; exit 1; }
[ "$BUILD_ONLY" = 1 ] && { echo "Built $APP"; exit 0; }
if [ -z "${DEVICE:-}" ]; then
	DEVICE="$(xcrun devicectl list devices | awk '/physical/ && /iPhone/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i }' | head -1)"
fi
[ -n "$DEVICE" ] || { echo "No paired iPhone; set DEVICE." >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Installed. Open moiraine on the phone and give it gaidin's tailnet name."
