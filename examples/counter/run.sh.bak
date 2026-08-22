#!/bin/bash
set -e

PLATFORM="${1:-macos}"
APP_NAME="Counter"
BUNDLE_ID="com.sui.counter"

echo "==> [1/4] Compiling Haxe (generates C++ & Swift)..."
haxe build.hxml

echo "==> [2/4] Assembling Xcode project..."
mkdir -p build/$PLATFORM/Sources
cp build/swift/*.swift build/$PLATFORM/Sources/

# Runtime stubs (standalone mode, no C++ bridge yet)
if [ ! -f build/$PLATFORM/Sources/HaxeRuntime.swift ]; then
cat > build/$PLATFORM/Sources/HaxeRuntime.swift << 'SWIFT'
import Foundation
public final class HaxeRuntime {
    public static func initialize() {
        print("[HaxeRuntime] Initialized (standalone mode)")
    }
}
SWIFT
fi

if [ ! -f build/$PLATFORM/Sources/HaxeBridge.swift ]; then
cat > build/$PLATFORM/Sources/HaxeBridge.swift << 'SWIFT'
import Foundation
import Observation
@Observable
public final class HaxeBridge {
    public static let shared = HaxeBridge()
    private var actions: [String: () -> Void] = [:]
    private init() {}
    public func invokeAction(_ name: String) {
        if let action = actions[name] { action() }
    }
}
SWIFT
fi

cat > build/$PLATFORM/project.yml << YAML
name: $APP_NAME
options:
  bundleIdPrefix: com.sui
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
settings:
  SWIFT_VERSION: "5.9"
targets:
  $APP_NAME:
    type: application
    platform: macOS
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
xcodebuild build \
  -project $APP_NAME.xcodeproj \
  -scheme $APP_NAME \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  -quiet

echo "==> [4/4] Launching..."
open DerivedData/Build/Products/Debug/$APP_NAME.app
