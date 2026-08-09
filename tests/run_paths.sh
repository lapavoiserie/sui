#!/usr/bin/env bash
#
# Checks that both render paths still answer.
#
# The dynamic one is the default and every example exercises it. This is for
# the other one: set aside is not removed, so a build that still asks for the
# transpiler must get it -- and must be told what it is asking for. Without a
# check here the path rots silently, and we learn about it from whoever was
# still on it.
#
#   ./tests/run_paths.sh
#
# Compiled under --interp: the macro runs on any target, and this asks which
# files it emits and what it says, not what hxcpp makes of them.

set -u
cd "$(dirname "$0")/.."
root=$(pwd)
failures=0

# Run from a scratch directory: SwiftGenerator emits a whole project tree
# relative to the working directory.
compile() {
	local work out code
	work=$(mktemp -d)
	out=$(cd "$work" && haxe -cp "$root/src" -cp "$root/tests/paths" -lib rui -lib nui \
		--macro 'sui.macros.SwiftGenerator.register()' -main PathFixture --interp "$@" 2>&1)
	code=$?
	rm -rf "$work"
	printf '%s\n' "$out"
	return $code
}

echo "sui — render paths"

if out=$(compile); then
	if echo "$out" | grep -q "decommissioned"; then
		echo "  FAIL the default path warned about the decommissioned one"; failures=1
	else
		echo "  ok   the dynamic renderer is the default, and says nothing about it"
	fi
else
	echo "  FAIL the default path should have compiled"; echo "$out" | sed 's/^/         /'; failures=1
fi

if out=$(compile -D sui_static); then
	if echo "$out" | grep -q "decommissioned"; then
		echo "  ok   -D sui_static builds, and says it is decommissioned"
	else
		echo "  FAIL -D sui_static built without saying the path is decommissioned"
		echo "$out" | sed 's/^/         /'; failures=1
	fi
else
	echo "  FAIL -D sui_static should still compile -- it is set aside, not removed"
	echo "$out" | sed 's/^/         /'; failures=1
fi

# Both defines is a leftover, not a preference: guessing either way builds
# something nobody asked for.
if out=$(compile -D sui_static -D sui_hot_reload); then
	echo "  FAIL contradictory defines should have been refused"; failures=1
elif echo "$out" | grep -q "contradict"; then
	echo "  ok   -D sui_static with -D sui_hot_reload is refused"
else
	echo "  FAIL refused, but not for the stated reason"; echo "$out" | sed 's/^/         /'; failures=1
fi

# The old opt-in still names what already happens, so an untouched build.hxml
# keeps working.
if out=$(compile -D sui_hot_reload); then
	echo "  ok   -D sui_hot_reload is accepted, and is a no-op"
else
	echo "  FAIL -D sui_hot_reload should still be accepted"; echo "$out" | sed 's/^/         /'; failures=1
fi

[ $failures -eq 0 ] || { echo ""; echo "render paths: failed"; exit 1; }
echo ""
echo "all good"
