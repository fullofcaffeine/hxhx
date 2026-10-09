#!/usr/bin/env bash
set -euo pipefail

# Fixed process profiles prove attribution and deduplication independently of
# host load. The lifecycle fixture separately observes real owned processes.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/hxhx/stage0-process-resources.sh"

ps() {
	cat <<'PROCESSES'
100 1000000 0.1 S
110 8192 0.2 S
200 200000 0.5 S
201 64000 80.5 R
202 128000 10.5 R
201 64000 80.5 R
999 9999999 999.0 R
PROCESSES
}

server="$(stage0_sample_process_resources 100 '100 110 200 201 202 201' '200 201 202 110')"
[ "$server" = '201|64000|80.5|R|1400192|91.8|server-worker' ] || {
	echo "incorrect server attribution or duplicate PID total: $server" >&2
	exit 1
}

direct="$(stage0_sample_process_resources 100 '100 110' '')"
[ "$direct" = '100|1000000|0.1|S|1008192|0.3|client-tree' ] || {
	echo "direct-process reporting changed: $direct" >&2
	exit 1
}

absent="$(stage0_sample_process_resources 300 '300' '')"
[ "$absent" = '300||||0||client-tree' ] || {
	echo "missing process must not receive invented measurements: $absent" >&2
	exit 1
}

echo 'STAGE0_PROCESS_RESOURCES_FIXTURE:PASS'
