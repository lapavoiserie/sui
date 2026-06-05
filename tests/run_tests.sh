#!/bin/bash
set -e

cd "$(dirname "$0")"
PASS=0
FAIL=0

echo "=== sui test suite ==="
echo ""

# Test 1: Haxe compilation + Swift generation
echo "--- Test 1: Compile and generate Swift ---"
rm -rf build
haxe build.hxml 2>&1 | tail -1

if [ ! -f build/swift/App.swift ] || [ ! -f build/swift/ContentView.swift ]; then
    echo "FAIL: Swift files not generated"
    FAIL=$((FAIL + 1))
else
    echo "PASS: Swift files generated"
    PASS=$((PASS + 1))
fi

# Test 2: App.swift matches expected
echo ""
echo "--- Test 2: App.swift content ---"
if diff -u expected/App.swift build/swift/App.swift > /dev/null 2>&1; then
    echo "PASS: App.swift matches expected"
    PASS=$((PASS + 1))
else
    echo "FAIL: App.swift differs from expected"
    diff -u expected/App.swift build/swift/App.swift || true
    FAIL=$((FAIL + 1))
fi

# Test 3: ContentView.swift matches expected
echo ""
echo "--- Test 3: ContentView.swift content ---"
if diff -u expected/ContentView.swift build/swift/ContentView.swift > /dev/null 2>&1; then
    echo "PASS: ContentView.swift matches expected"
    PASS=$((PASS + 1))
else
    echo "FAIL: ContentView.swift differs from expected"
    diff -u expected/ContentView.swift build/swift/ContentView.swift || true
    FAIL=$((FAIL + 1))
fi

# Test 4: Action closures force bridge mode — AppState is generated
# with didSet write-back hooks (Swift bindings → Haxe mirror).
echo ""
echo "--- Test 4: AppState generation + write-back ---"
if grep -q "@Bindable var appState = AppState.shared" build/swift/ContentView.swift \
   && grep -q 'HaxeBridgeC.syncState("count", String(count))' build/swift/AppState.swift; then
    echo "PASS: AppState + syncState didSet generated"
    PASS=$((PASS + 1))
else
    echo "FAIL: AppState/syncState not found"
    FAIL=$((FAIL + 1))
fi

# Test 5: State interpolation in Text
echo ""
echo "--- Test 5: State interpolation ---"
if grep -q 'Text("Value: \\(appState.count)")' build/swift/ContentView.swift; then
    echo "PASS: State interpolation generated"
    PASS=$((PASS + 1))
else
    echo "FAIL: State interpolation not found"
    FAIL=$((FAIL + 1))
fi

# Test 6: Action closures — Swift dispatches by explicit id and the
# SAME id is registered on the Haxe side (Callbacks.reg in the C++).
echo ""
echo "--- Test 6: Action closure dispatch + id match ---"
IDS=$(grep -o 'HaxeBridgeC.invokeAction([0-9]*)' build/swift/ContentView.swift | grep -o '[0-9]*')
MATCH=1
if [ -z "$IDS" ]; then MATCH=0; fi
for id in $IDS; do
    if ! grep -q "Callbacks_obj::reg(.*$id" build/cpp/src/TestSwiftGen.cpp; then
        echo "MISSING runtime registration for action id $id"
        MATCH=0
    fi
done
if [ $MATCH -eq 1 ]; then
    echo "PASS: every Swift action id has a Haxe-side registration"
    PASS=$((PASS + 1))
else
    echo "FAIL: action id mismatch between Swift and Haxe"
    FAIL=$((FAIL + 1))
fi

# Test 7: CLI compiles
echo ""
echo "--- Test 7: CLI compilation ---"
cd ..
if haxe -cp tools -cp src -main tools.cli.CLI -neko "${TMPDIR:-/tmp}/cli_test.n" 2>&1; then
    echo "PASS: CLI compiles"
    PASS=$((PASS + 1))
else
    echo "FAIL: CLI compilation failed"
    FAIL=$((FAIL + 1))
fi

# Test 8: Shared memory bridge tests
echo ""
echo "--- Test 8: Shared memory bridge ---"
cd tests
if haxe -cp . -cp ../src -main TestSharedMemory -neko "${TMPDIR:-/tmp}/test_shared_memory.n" 2>&1 && neko "${TMPDIR:-/tmp}/test_shared_memory.n" 2>&1; then
    echo "PASS: Shared memory tests passed"
    PASS=$((PASS + 1))
else
    echo "FAIL: Shared memory tests failed"
    FAIL=$((FAIL + 1))
fi

# Test 9: Typed-expression emission (Text.bind, ForEach.byIndex,
# qualifyStateName, ternary temp-var reconstruction). Bridge mode
# forces appState. prefixing — verifies the rewriter-free codepath.
echo ""
echo "--- Test 9: Typed-expression bridge mode ---"
cd typed-expressions
rm -rf build
haxe build.hxml 2>&1 | tail -1
if [ ! -f build/swift/ContentView.swift ]; then
    echo "FAIL: typed-expressions Swift files not generated"
    FAIL=$((FAIL + 1))
elif diff -u expected/ContentView.swift build/swift/ContentView.swift > /dev/null 2>&1; then
    echo "PASS: typed-expressions ContentView.swift matches expected"
    PASS=$((PASS + 1))
else
    echo "FAIL: typed-expressions ContentView.swift differs from expected"
    diff -u expected/ContentView.swift build/swift/ContentView.swift || true
    FAIL=$((FAIL + 1))
fi
cd ..

# Test 10: typed-expressions output has no rewriter placeholder /
# no double-prefix / no stringly state names — keystone properties
# that prove `qualifyStateName` did its job at every emit site.
echo ""
echo "--- Test 10: No rewriter artefacts in typed-expressions ---"
LEAKS=0
if grep -q "__APPSTATE__" typed-expressions/build/swift/ContentView.swift; then
    echo "FAIL: __APPSTATE__ placeholder leaked into ContentView.swift"
    LEAKS=$((LEAKS + 1))
fi
if grep -q "appState\.appState" typed-expressions/build/swift/ContentView.swift; then
    echo "FAIL: appState.appState double-prefix in ContentView.swift"
    LEAKS=$((LEAKS + 1))
fi
if [ $LEAKS -eq 0 ]; then
    echo "PASS: no rewriter artefacts"
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + LEAKS))
fi

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
