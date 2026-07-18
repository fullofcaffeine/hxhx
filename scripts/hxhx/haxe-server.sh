#!/usr/bin/env bash
set -euo pipefail

# Manages one repository-owned Haxe compilation server. A live server is only
# reused when it was started with the same Haxe executable requested now;
# otherwise the helper restarts it so callers cannot silently change labels
# while continuing to use an older wrapper or compiler binary.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${HXHX_STATE_DIR:-$ROOT/.hxhx/state}"
HAXE_BIN="${HAXE_BIN:-haxe}"
HXHX_HAXE_SERVER_PORT="${HXHX_HAXE_SERVER_PORT:-}"
PORT_FILE="$STATE_DIR/haxe-server.port"
PID_FILE="$STATE_DIR/haxe-server.pid"
PIDS_FILE="$STATE_DIR/haxe-server.pids"
BIN_FILE="$STATE_DIR/haxe-server.bin"
LOG_FILE="$STATE_DIR/haxe-server.log"
START_IN_PROGRESS=0

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/haxe-server.sh <command> [options]

Commands:
  start             Start/reuse a matching repo-owned haxe --wait server.
  stop              Stop repo-owned haxe --wait server if running.
  status            Print server status (running/not-running).
  port              Print resolved server port.
  connect-arg       Print a ready-to-use "--connect <port>" argument.

Environment knobs:
  HAXE_BIN                  Haxe executable path (default: haxe)
  HXHX_STATE_DIR            State directory (default: .hxhx/state)
  HXHX_HAXE_SERVER_PORT     Override server port (default: deterministic per-repo)
USAGE
}

ensure_state_dir() {
	mkdir -p "$STATE_DIR"
}

resolve_haxe_identity() {
	local resolved
	resolved="$(command -v "$HAXE_BIN" 2>/dev/null || true)"
	if [ -z "$resolved" ]; then
		echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
		return 1
	fi
	local resolved_dir
	resolved_dir="$(cd "$(dirname "$resolved")" && pwd -P)"
	printf '%s/%s\n' "$resolved_dir" "$(basename "$resolved")"
}

read_server_identity() {
	if [ ! -s "$BIN_FILE" ]; then
		return 1
	fi
	cat "$BIN_FILE"
}

is_pid_alive() {
	local pid="$1"
	kill -0 "$pid" >/dev/null 2>&1
}

resolve_default_port() {
	local checksum
	checksum="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
	echo $((17100 + (checksum % 500)))
}

resolve_port() {
	if [ -n "$HXHX_HAXE_SERVER_PORT" ]; then
		echo "$HXHX_HAXE_SERVER_PORT"
		return
	fi
	if [ -f "$PORT_FILE" ]; then
		local file_port
		file_port="$(cat "$PORT_FILE")"
		case "$file_port" in
			''|*[!0-9]*)
				;;
			*)
				echo "$file_port"
				return
				;;
		esac
	fi
	resolve_default_port
}

save_port() {
	local port="$1"
	ensure_state_dir
	printf '%s\n' "$port" >"$PORT_FILE"
}

pid_looks_like_haxe_wait() {
	local pid="$1"
	local port="$2"
	local cmd
	cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
	if [ -z "$cmd" ]; then
		return 1
	fi
	printf '%s\n' "$cmd" | awk -v expected_port="$port" '
		index(tolower($0), "haxe") == 0 { exit 1 }
		{
			for (i = 1; i < NF; i++) {
				if ($i == "--wait" && $(i + 1) == expected_port)
					exit 0
			}
			exit 1
		}
	'
}

read_recorded_pids() {
	{
		if [ -s "$PID_FILE" ]; then
			cat "$PID_FILE"
		fi
		if [ -s "$PIDS_FILE" ]; then
			cat "$PIDS_FILE"
		fi
	} | awk '/^[0-9]+$/ && !seen[$1]++ { print $1 }'
}

collect_process_tree_pids() {
	local root_pid="$1"
	local frontier="$root_pid"
	local seen=" $root_pid "
	local collected="$root_pid"
	local parent_pid=""
	local child_pids=""
	local child_pid=""
	local next_frontier=""

	while [ -n "$frontier" ]; do
		next_frontier=""
		for parent_pid in $frontier; do
			child_pids="$(pgrep -P "$parent_pid" 2>/dev/null || true)"
			for child_pid in $child_pids; do
				if [[ "$seen" == *" $child_pid "* ]]; then
					continue
				fi
				seen="${seen}${child_pid} "
				collected="${collected} ${child_pid}"
				next_frontier="${next_frontier} ${child_pid}"
			done
		done
		frontier="$(printf '%s\n' "$next_frontier" | xargs 2>/dev/null || true)"
	done

	printf '%s\n' "$collected" | tr ' ' '\n' | awk '/^[0-9]+$/ && !seen[$1]++ { print $1 }'
}

record_server_processes() {
	local root_pid="$1"
	local temporary="$PIDS_FILE.tmp.$$"
	collect_process_tree_pids "$root_pid" >"$temporary"
	mv "$temporary" "$PIDS_FILE"
}

collect_owned_process_pids() {
	local port="$1"
	local pid=""
	local collected=""
	while IFS= read -r pid; do
		if ! is_pid_alive "$pid" || ! pid_looks_like_haxe_wait "$pid" "$port"; then
			continue
		fi
		collected="${collected}$(collect_process_tree_pids "$pid")"$'\n'
	done < <(read_recorded_pids)
	printf '%s' "$collected" | awk '/^[0-9]+$/ && !seen[$1]++ { print $1 }'
}

read_running_pid() {
	local port="$1"
	local pid=""
	while IFS= read -r pid; do
		if is_pid_alive "$pid" && pid_looks_like_haxe_wait "$pid" "$port"; then
			printf '%s\n' "$pid"
			return 0
		fi
	done < <(read_recorded_pids)
	return 1
}

signal_processes() {
	local signal="$1"
	local pids="$2"
	local pid=""
	printf '%s\n' "$pids" | awk 'NF { rows[++count] = $1 } END { for (i = count; i >= 1; i--) print rows[i] }' |
		while IFS= read -r pid; do
			kill "$signal" "$pid" >/dev/null 2>&1 || true
		done
}

living_pids() {
	local pids="$1"
	local pid=""
	while IFS= read -r pid; do
		if [ -n "$pid" ] && is_pid_alive "$pid"; then
			printf '%s\n' "$pid"
		fi
	done <<<"$pids"
}

wait_for_server_ready() {
	local port="$1"
	local attempts=40
	local i=0
	while [ "$i" -lt "$attempts" ]; do
		if "$HAXE_BIN" --connect "$port" --version >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.2
	done
	return 1
}

start_server() {
	local requested_identity
	requested_identity="$(resolve_haxe_identity)"
	ensure_state_dir

	local existing_pid
	local port
	port="$(resolve_port)"
	save_port "$port"
	existing_pid="$(read_running_pid "$port" || true)"

	if [ -n "$existing_pid" ]; then
		local existing_identity
		existing_identity="$(read_server_identity || true)"
		if [ "$existing_identity" = "$requested_identity" ]; then
			echo "haxe-server: already running pid=$existing_pid port=$port haxe_bin=$requested_identity" >&2
			return 0
		fi
		echo "haxe-server: selected Haxe changed; restarting old=${existing_identity:-unknown} new=$requested_identity" >&2
		stop_server
	fi

	echo "haxe-server: starting port=$port haxe_bin=$requested_identity" >&2
	nohup "$HAXE_BIN" --wait "$port" >"$LOG_FILE" 2>&1 &
	local pid="$!"
	printf '%s\n' "$pid" >"$PID_FILE"
	printf '%s\n' "$pid" >"$PIDS_FILE"
	printf '%s\n' "$requested_identity" >"$BIN_FILE"
	START_IN_PROGRESS=1

	if ! wait_for_server_ready "$port"; then
		echo "haxe-server: failed to become ready at port=$port (pid=$pid)." >&2
		exit 1
	fi

	record_server_processes "$pid"
	START_IN_PROGRESS=0
	echo "haxe-server: ready pid=$pid port=$port haxe_bin=$requested_identity" >&2
}

stop_server() {
	local port
	port="$(resolve_port)"
	local pids
	pids="$(collect_owned_process_pids "$port")"
	if [ -z "$pids" ]; then
		rm -f "$PID_FILE" "$PIDS_FILE" "$BIN_FILE"
		echo "haxe-server: not-running" >&2
		return 0
	fi
	local pid
	pid="$(printf '%s\n' "$pids" | head -n 1)"
	echo "haxe-server: stopping pid=$pid" >&2
	signal_processes -TERM "$pids"
	local remaining="$pids"
	local attempt=0
	while [ "$attempt" -lt 10 ]; do
		remaining="$(living_pids "$remaining")"
		if [ -z "$remaining" ]; then
			break
		fi
		attempt=$((attempt + 1))
		sleep 0.1
	done
	if [ -n "$remaining" ]; then
		signal_processes -KILL "$remaining"
	fi
	rm -f "$PID_FILE" "$PIDS_FILE" "$BIN_FILE"
}

status_server() {
	local endpoint
	endpoint="$(resolve_port)"
	local pid
	pid="$(read_running_pid "$endpoint" || true)"
	if [ -n "$pid" ]; then
		local identity
		identity="$(read_server_identity || true)"
		echo "running pid=$pid port=$endpoint haxe_bin=${identity:-unknown}"
		return 0
	fi
	echo "not-running port=$endpoint"
	return 1
}

print_port() {
	resolve_port
}

print_connect_arg() {
	local endpoint
	endpoint="$(print_port)"
	echo "--connect $endpoint"
}

on_exit() {
	local code="$?"
	if [ "$START_IN_PROGRESS" = "1" ]; then
		START_IN_PROGRESS=0
		stop_server >/dev/null 2>&1 || true
	fi
	return "$code"
}

trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

case "$1" in
	start)
		start_server
		;;
	stop)
		stop_server
		;;
	status)
		status_server
		;;
	port)
		print_port
		;;
	connect-arg)
		print_connect_arg
		;;
	-h|--help)
		usage
		;;
	*)
		echo "Unknown command: $1" >&2
		usage >&2
		exit 1
		;;
esac
