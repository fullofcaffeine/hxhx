#!/usr/bin/env bash

# Process watchdog used by stage0 bootstrap regeneration.
#
# Why this exists:
# A full hxhx bootstrap can spend more than 15 minutes compiling without
# writing to its log. An elapsed-time-only "hang" limit can therefore kill a
# healthy compiler. Removing all limits would have the opposite problem: a
# genuinely stuck compiler could occupy CPU, memory, and CI capacity forever.
#
# What this module decides:
# The soft stall limit resets when an observed compiler process accumulates CPU
# time, grows its log, or changes process shape. The caller supplies one client
# root and can add already-verified PIDs from a separate owned compilation
# server. The separate hard limit always measures total elapsed time and cannot
# be extended by progress. Timeout cleanup in this module remains limited to
# the client tree; the caller owns cleanup for any separately managed server.
#
# How ownership is divided:
# The regeneration script starts the compiler, calls these functions once per
# second, owns `wait`, writes diagnostics and JSON reports, and chooses the
# configured limits. This focused module observes a bounded process-table
# snapshot, records why progress was recognized, decides which limit fired,
# and stops only the supplied process tree when asked. It never starts a
# compiler, chooses policy defaults, or writes build output.

stage0_watchdog_collect_process_tree_pids() {
	local root_pid="$1"

	# Work from one process-table snapshot. Repeatedly invoking pgrep while
	# walking a busy compiler can chase short-lived descendants and make the
	# observer itself expensive or non-terminating. The fixed snapshot makes
	# collection bounded while still finding children at every depth.
	ps -axo pid=,ppid= 2>/dev/null \
		| awk -v root_pid="$root_pid" '
			{
				pids[NR] = $1
				parents[NR] = $2
			}
			END {
				in_tree[root_pid] = 1
				order[++count] = root_pid
				changed = 1
				while (changed) {
					changed = 0
					for (i = 1; i <= NR; i++) {
						pid = pids[i]
						parent = parents[i]
						if (!in_tree[pid] && in_tree[parent]) {
							in_tree[pid] = 1
							order[++count] = pid
							changed = 1
						}
					}
				}
				for (i = 1; i <= count; i++) {
					printf "%s%s", (i == 1 ? "" : " "), order[i]
				}
				printf "\n"
			}
		'
}

# Return the foreground client tree plus any additional PIDs whose ownership
# the caller already verified. This module must not discover unrelated Haxe
# servers by command name, port, or executable spelling.
stage0_watchdog_collect_observed_pids() {
	local root_pid="$1"
	local additional_owned_pids="${2:-}"

	{
		stage0_watchdog_collect_process_tree_pids "$root_pid" | tr ' ' '\n'
		printf '%s\n' "$additional_owned_pids" | tr ' ' '\n'
	} | awk '
		/^[0-9]+$/ && !seen[$1]++ { ordered[++count] = $1 }
		END {
			for (i = 1; i <= count; i++)
				printf "%s%s", (i == 1 ? "" : " "), ordered[i]
			printf "\n"
		}
	'
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
	local additional_owned_pids="${4:-}"

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
	tree_pids="$(stage0_watchdog_collect_observed_pids "$root_pid" "$additional_owned_pids")"
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
