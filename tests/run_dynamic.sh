#!/usr/bin/env bash
#
# Checks the Haxe half of sui's dynamic renderer.
#
# Everything it covers is reached from Swift through a C bridge, by symbol, so
# no Haxe compiler sees the way it is used -- and the failure mode is a node
# drawn wrong or not at all, never a crash. See tests/NuiCheck.hx.
#
#   ./tests/run_dynamic.sh
#
# The walk is plain Haxe: no hxcpp, no Xcode, so it runs under --interp and
# answers in a second.

set -u
cd "$(dirname "$0")/.."

# -D sui_hot_reload so LiveProps runs: the deferral it performs is one of the
# things under test, and without it the checks would pass by describing a
# build nobody ships.
haxe -cp src -cp tests -lib rui -lib nui -D sui_hot_reload --interp -main NuiCheck
