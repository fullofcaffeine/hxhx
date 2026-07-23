#!/usr/bin/env bash

# Process watchdog used by stage0 bootstrap regeneration.
#
# Callers start the compiler and keep ownership of `wait`. This module only
# observes the owned process tree, decides whether a stall or absolute timeout
# has fired, and terminates that same tree when asked.

stage0_watchdog_collect_process_tree_pids() {
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
			if [ -z "$child_pids" ]; then
				continue
			fi
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

	printf '%s\n' "$collected"
}

stage0_watchdog_process_tree_cpu_signature() {
	local tree_pids="$1"
	local tree_pid=""
	local cpu_time=""
	local signature=""

	for tree_pid in $tree_pids; do
		cpu_time="$(ps -o time= -p "$tree_pid" 2>/dev/null | tr -d ' ' || true)"
		if [ -n "$cpu_time" ]; then
			signature="${signature}${tree_pid}:${cpu_time};"
		fi
	done

	printf '%s\n' "$signature"
}

stage0_watchdog_init() {
	STAGE0_WATCHDOG_TIMEOUT_KIND="none"
	STAGE0_WATCHDOG_TIMEOUT_ELAPSED=0
	STAGE0_WATCHDOG_LAST_PROGRESS_ELAPSED=0
	STAGE0_WATCHDOG_LAST_PROGRESS_REASON="process-start"
	STAGE0_WATCHDOG_CLEANUP="not-needed"
	STAGE0_WATCHDOG_POLL_ELAPSED=0
	STAGE0_WATCHDOG_PREVIOUS_CPU_SIGNATURE=""
	STAGE0_WATCHDOG_PREVIOUS_LOG_BYTES=0
	STAGE0_WATCHDOG_PREVIOUS_TREE_PIDS=""
	STAGE0_WATCHDOG_TERMINATED_TREE_PIDS=""
}

stage0_watchdog_poll() {
	local elapsed="$1"
	local root_pid="$2"
	local log_file="$3"

	if [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ] \
		&& [ "$elapsed" -ge "$HXHX_STAGE0_FAILFAST_SECS" ]; then
		STAGE0_WATCHDOG_TIMEOUT_KIND="hard"
		STAGE0_WATCHDOG_TIMEOUT_ELAPSED="$elapsed"
		return
	fi

	STAGE0_WATCHDOG_POLL_ELAPSED="$((STAGE0_WATCHDOG_POLL_ELAPSED + 1))"
	if [ "$STAGE0_WATCHDOG_POLL_ELAPSED" -lt "$HXHX_STAGE0_PROGRESS_POLL_SECS" ]; then
		return
	fi
	STAGE0_WATCHDOG_POLL_ELAPSED=0

	local tree_pids
	tree_pids="$(stage0_watchdog_collect_process_tree_pids "$root_pid")"
	local cpu_signature
	cpu_signature="$(stage0_watchdog_process_tree_cpu_signature "$tree_pids")"
	local log_bytes
	log_bytes="$(wc -c <"$log_file" 2>/dev/null | tr -d ' ' || true)"
	log_bytes="${log_bytes:-0}"

	if [ -n "$STAGE0_WATCHDOG_PREVIOUS_CPU_SIGNATURE" ] \
		&& [ "$cpu_signature" != "$STAGE0_WATCHDOG_PREVIOUS_CPU_SIGNATURE" ]; then
		STAGE0_WATCHDOG_LAST_PROGRESS_ELAPSED="$elapsed"
		STAGE0_WATCHDOG_LAST_PROGRESS_REASON="cpu-time"
	elif [ "$log_bytes" -gt "$STAGE0_WATCHDOG_PREVIOUS_LOG_BYTES" ]; then
		STAGE0_WATCHDOG_LAST_PROGRESS_ELAPSED="$elapsed"
		STAGE0_WATCHDOG_LAST_PROGRESS_REASON="log-growth"
	elif [ -n "$STAGE0_WATCHDOG_PREVIOUS_TREE_PIDS" ] \
		&& [ "$tree_pids" != "$STAGE0_WATCHDOG_PREVIOUS_TREE_PIDS" ]; then
		STAGE0_WATCHDOG_LAST_PROGRESS_ELAPSED="$elapsed"
		STAGE0_WATCHDOG_LAST_PROGRESS_REASON="process-tree"
	fi

	STAGE0_WATCHDOG_PREVIOUS_CPU_SIGNATURE="$cpu_signature"
	STAGE0_WATCHDOG_PREVIOUS_LOG_BYTES="$log_bytes"
	STAGE0_WATCHDOG_PREVIOUS_TREE_PIDS="$tree_pids"

	if [ "$HXHX_STAGE0_STALL_TIMEOUT_SECS" != "0" ] \
		&& [ "$((elapsed - STAGE0_WATCHDOG_LAST_PROGRESS_ELAPSED))" -ge "$HXHX_STAGE0_STALL_TIMEOUT_SECS" ]; then
		STAGE0_WATCHDOG_TIMEOUT_KIND="stall"
		STAGE0_WATCHDOG_TIMEOUT_ELAPSED="$elapsed"
	fi
}

stage0_watchdog_pid_is_active() {
	local pid="$1"
	local state=""
	state="$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
	[ -n "$state" ] && [ "$state" != "Z" ]
}

stage0_watchdog_terminate_process_tree() {
	local root_pid="$1"
	local tree_pids=""
	local -a pids=()
	local index=0
	local pid=""

	tree_pids="$(stage0_watchdog_collect_process_tree_pids "$root_pid")"
	read -r -a pids <<<"$tree_pids"
	STAGE0_WATCHDOG_TERMINATED_TREE_PIDS="$tree_pids"

	for ((index = ${#pids[@]} - 1; index >= 0; index--)); do
		kill -TERM "${pids[$index]}" 2>/dev/null || true
	done
	sleep 1 || true
	for ((index = ${#pids[@]} - 1; index >= 0; index--)); do
		pid="${pids[$index]}"
		if stage0_watchdog_pid_is_active "$pid"; then
			kill -KILL "$pid" 2>/dev/null || true
		fi
	done
}

stage0_watchdog_record_cleanup_result() {
	local pid=""
	STAGE0_WATCHDOG_CLEANUP="complete"
	for pid in $STAGE0_WATCHDOG_TERMINATED_TREE_PIDS; do
		if stage0_watchdog_pid_is_active "$pid"; then
			STAGE0_WATCHDOG_CLEANUP="incomplete"
			return
		fi
	done
}
