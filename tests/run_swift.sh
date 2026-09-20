#!/usr/bin/env bash
#
# The Swift runtime type-checks. Not "reads correctly" -- compiles.
#
#   ./tests/run_swift.sh
#
# This half of `sui` was unverifiable here for as long as anyone had looked:
# every commit touching `runtime/` said "read, not compiled". It is not true
# any more, and the three things that make it work are worth writing down.
#
#   1. The Command Line Tools toolchain is not enough. `@State` is a macro,
#      and its plugin ships with Xcode: without it every `@State` in the file
#      fails with "plugin for module 'SwiftUIMacros' not found".
#   2. So the toolchain is taken from Xcode directly, WITHOUT `xcode-select
#      -s` -- that needs sudo and changes the whole machine for one check.
#   3. The `viewnode_*` functions are C, reached through a bridging header.
#      Without it, 96 errors that are all the same missing symbol.
#
# It type-checks; it does not run, and nothing here has been seen on a screen.

set -u
cd "$(dirname "$0")/.."

XC=""
for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
	if [ -x "$candidate/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
		XC="$candidate/Contents/Developer"
		break
	fi
done

if [ -z "$XC" ]; then
	echo "skip no Xcode toolchain: the Command Line Tools alone cannot expand @State"
	exit 0
fi

"$XC/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -typecheck \
	-sdk "$XC/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
	-import-objc-header runtime/ViewNodeBridgeC.h \
	runtime/DynamicView.swift runtime/swift/*.swift || {
		echo ""
		echo "failed"
		exit 1
	}

echo "ok   the Swift runtime type-checks ($(basename "$XC" | head -c 0)$XC)"
echo ""
echo "all good"
