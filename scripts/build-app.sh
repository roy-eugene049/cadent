#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path --sdk macosx)"
APP="build/Cadent.app"
MACOS="$APP/Contents/MacOS"
mkdir -p "$MACOS"
cp Cadent/Info.plist "$APP/Contents/Info.plist"

SWIFT_FLAGS=(-swift-version 6 -parse-as-library -g -target arm64-apple-macos14.0 -sdk "$SDK")
if [[ "${CONFIGURATION:-debug}" == "release" ]]; then
  SWIFT_FLAGS+=(-O)
else
  SWIFT_FLAGS+=(-Onone -D DEBUG)
fi

swiftc \
  "${SWIFT_FLAGS[@]}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework ServiceManagement \
  -framework CoreAudio \
  -o "$MACOS/Cadent" \
  Cadent/Log.swift \
  Cadent/AppModel.swift \
  Cadent/CadentApp.swift

codesign --force --sign - --entitlements Cadent/Cadent.entitlements "$APP"
echo "Built $APP"
