#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${HXHX_STATE_DIR:-$ROOT/.hxhx/state}"
HAXE_BIN="${HAXE_BIN:-haxe}"
HXHX_HAXE_SERVER_PORT="${HXHX_HAXE_SERVER_PORT:-}"
PORT_FILE="$STATE_DIR/haxe-server.port"
PID_FILE="$STATE_DIR/haxe-server.pid"
LOG_FILE="$STATE_DIR/haxe-server.log"

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/haxe-server.sh <command> [options]

Commands:
  start             Start repo-owned haxe --wait server if not already running.
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
	local cmd
	cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
	if [ -z "$cmd" ]; then
		return 1
	fi
	case "$cmd" in
		*haxe*--wait*)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

read_running_pid() {
	if [ ! -f "$PID_FILE" ]; then
		return 1
	fi
	local pid
	pid="$(cat "$PID_FILE")"
	case "$pid" in
		''|*[!0-9]*)
			return 1
			;;
	esac
	if ! is_pid_alive "$pid"; then
		return 1
	fi
	if ! pid_looks_like_haxe_wait "$pid"; then
		return 1
	fi
	printf '%s\n' "$pid"
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
	if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
		echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
		exit 1
	fi
	ensure_state_dir

	local existing_pid
	existing_pid="$(read_running_pid || true)"
	local port
	port="$(resolve_port)"
	save_port "$port"

	if [ -n "$existing_pid" ]; then
		echo "haxe-server: already running pid=$existing_pid port=$port" >&2
		return 0
	fi

	echo "haxe-server: starting port=$port" >&2
	nohup "$HAXE_BIN" --wait "$port" >"$LOG_FILE" 2>&1 &
	local pid="$!"
	printf '%s\n' "$pid" >"$PID_FILE"

	if ! wait_for_server_ready "$port"; then
		echo "haxe-server: failed to become ready at port=$port (pid=$pid)." >&2
		kill "$pid" >/dev/null 2>&1 || true
		sleep 0.2
		kill -9 "$pid" >/dev/null 2>&1 || true
		rm -f "$PID_FILE"
		exit 1
	fi

	echo "haxe-server: ready pid=$pid port=$port" >&2
}

stop_server() {
	local pid
	pid="$(read_running_pid || true)"
	if [ -z "$pid" ]; then
		rm -f "$PID_FILE"
		echo "haxe-server: not-running" >&2
		return 0
	fi
	echo "haxe-server: stopping pid=$pid" >&2
	kill "$pid" >/dev/null 2>&1 || true
	sleep 0.5
	if is_pid_alive "$pid"; then
		kill -9 "$pid" >/dev/null 2>&1 || true
	fi
	rm -f "$PID_FILE"
}

status_server() {
	local endpoint
	endpoint="$(resolve_port)"
	local pid
	pid="$(read_running_pid || true)"
	if [ -n "$pid" ]; then
		echo "running pid=$pid port=$endpoint"
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
