#!/bin/bash
set -e

PLATFORM="${1:-ios}"
APP_NAME="MyTabs"
BUNDLE_ID="com.sui.iostabs"

echo "==> [1/4] Compiling Haxe (generates C++ & Swift)..."
haxe build.hxml

echo "==> [2/4] Assembling Xcode project..."
mkdir -p build/$PLATFORM/Sources
cp build/swift/*.swift build/$PLATFORM/Sources/

if [ ! -f build/$PLATFORM/Sources/HaxeRuntime.swift ]; then
cat > build/$PLATFORM/Sources/HaxeRuntime.swift << 'SWIFT'
import Foundation
public final class HaxeRuntime {
    public static func initialize() {}
}
SWIFT
fi

if [ ! -f build/$PLATFORM/Sources/HaxeBridge.swift ]; then
cp ../../runtime/swift/HaxeBridge.swift build/$PLATFORM/Sources/
cp ../../runtime/swift/ViewBridge.swift build/$PLATFORM/Sources/
fi

# Platform settings
DEPLOY_TARGET="17.0"
PLATFORM_KEY="iOS"
DESTINATION="platform=iOS Simulator,name=iPhone 16"

if [ "$PLATFORM" = "ipad" ]; then
  PLATFORM="ios"  # iPadOS is iOS in Xcode
  DESTINATION="platform=iOS Simulator,name=iPad (10th generation)"
fi

if [ "$PLATFORM" = "macos" ]; then
  DEPLOY_TARGET="14.0"
  PLATFORM_KEY="macOS"
  DESTINATION=""
fi

cat > build/$PLATFORM/project.yml << YAML
name: $APP_NAME
options:
  bundleIdPrefix: com.sui
  deploymentTarget:
    $PLATFORM_KEY: "$DEPLOY_TARGET"
  xcodeVersion: "15.0"
settings:
  SWIFT_VERSION: "5.9"
targets:
  $APP_NAME:
    type: application
    platform: $PLATFORM_KEY
    sources:
      - path: Sources
        type: group
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
      GENERATE_INFOPLIST_FILE: true
YAML

cd build/$PLATFORM
xcodegen generate 2>&1 | grep -v "^$"
cd ../..

echo "==> [3/4] Building with Xcode..."
cd build/$PLATFORM

DEST_ARGS=""
if [ -n "$DESTINATION" ]; then
  DEST_ARGS="-destination '$DESTINATION'"
fi

eval xcodebuild build \
  -project $APP_NAME.xcodeproj \
  -scheme $APP_NAME \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  $DEST_ARGS \
  -quiet

echo "==> [4/4] Launching..."
cd ../..
if [ "$PLATFORM_KEY" = "macOS" ]; then
  open build/$PLATFORM/DerivedData/Build/Products/Debug/$APP_NAME.app
else
  DEVICE_NAME=$(echo "$DESTINATION" | sed 's/.*name=//')
  xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
  APP_PATH=$(find build/$PLATFORM/DerivedData -name "$APP_NAME.app" -type d | head -1)
  if [ -n "$APP_PATH" ]; then
    xcrun simctl install booted "$APP_PATH"
    xcrun simctl launch booted $BUNDLE_ID
    open -a Simulator
  else
    echo "Could not find built app"
  fi
fi
