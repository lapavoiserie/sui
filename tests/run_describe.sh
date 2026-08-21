#!/usr/bin/env bash
#
# Checks the sui end of the Companion pipe: describe (canonical nodes, with
# LiveProps thunks resolved) → snapshot → wire → the ids invoked the way a
# remote sink would. Judged on the exit code — the check prints its verdicts.
#
#   ./tests/run_describe.sh

set -u
cd "$(dirname "$0")/.."

haxe -cp tests -cp src \
	-lib mui -lib kui -lib rui -lib nui \
	-D mui_backend=sui \
	--macro "mui.macros.Bind.all()" \
	--macro "sui.kui.Platform.registerWithKui()" \
	-main DescribeCheck --interp
