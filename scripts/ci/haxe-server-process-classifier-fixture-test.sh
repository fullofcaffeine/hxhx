#!/usr/bin/env bash
set -euo pipefail

# Proves global Haxe-server preflight cannot mistake its caller (or another
# shell/test process) for a server just because the command text contains a
# server flag. This fixture is intentionally process-table-only so it never
# starts or signals a real process.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$ROOT/scripts/hxhx/haxe-server-processes.awk"

fail() {
	echo "HAXE_SERVER_PROCESS_CLASSIFIER:FAIL $*" >&2
	exit 1
}

[ -f "$CLASSIFIER" ] || fail "missing classifier: $CLASSIFIER"

actual="$(awk -f "$CLASSIFIER" <<'PROCESS_TABLE'
101 /opt/haxe /opt/haxe --wait 31101
102 haxe haxe --server-connect 31102
103 node node /repo/node_modules/.bin/haxe --wait 31103
104 /usr/bin/node /usr/bin/node /repo/haxeshim.js --server-connect 31104
201 /bin/bash /bin/bash -c echo haxe --wait 31201
202 zsh zsh scripts/cleanup-haxe --wait 31202
203 node node /repo/tools/not-haxe.js --wait 31203
204 haxe haxe -cp src -main Main
205 awk awk command-matcher haxe --wait 31205
PROCESS_TABLE
)"

expected=$'101\n102\n103\n104'
if [ "$actual" != "$expected" ]; then
	echo "Expected server PIDs:" >&2
	printf '%s\n' "$expected" >&2
	echo "Actual server PIDs:" >&2
	printf '%s\n' "$actual" >&2
	fail "classifier accepted a false positive or missed a real server"
fi

echo "HAXE_SERVER_PROCESS_CLASSIFIER:PASS"
