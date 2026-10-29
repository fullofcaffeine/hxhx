#!/usr/bin/env bash

# Sample resources for an already-owned client/server PID set. The caller owns
# identity validation, process discovery, waiting, and cleanup. This helper only
# reads a bounded PID set and never discovers servers by command name.
#
# Server mode focuses on the owned server process with the highest observed CPU
# percentage, breaking ties by RSS. Direct mode retains the highest-RSS focus.
# Totals count each observed PID once, including overlapping client/server sets.
# RSS sums can still count shared memory pages in different processes; they are
# sampled resident footprints, not unique physical memory or allocation totals.

stage0_sample_process_resources() {
	local client_pid="$1"
	local observed_pids="$2"
	local server_pids="${3:-}"
	local resource_pid
	# On macOS, measured individual PID queries cost less than a comma-separated
	# PID query. Read all needed fields once per supplied PID, then merge once.
	{
		for resource_pid in $observed_pids; do
			LC_ALL=C ps -o pid=,rss=,%cpu=,state= -p "$resource_pid" 2>/dev/null || true
		done
	} \
		| LC_ALL=C awk -v client="$client_pid" -v observed="$observed_pids" -v servers="$server_pids" '
			BEGIN {
				count = split(observed, values, " ")
				for (i = 1; i <= count; i++) allowed[values[i]] = 1
				count = split(servers, values, " ")
				for (i = 1; i <= count; i++) owned[values[i]] = 1
				focus = client
				role = "client-tree"
			}
			$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+([.][0-9]+)?$/ && allowed[$1] && !seen[$1]++ {
				pid = $1; rss[pid] = $2; cpu[pid] = $3; state[pid] = $4
				total_rss += $2; total_cpu += $3; samples++
				if (samples == 1 || $2 > rss[focus]) focus = pid
				if (owned[pid] && (!worker || $3 > cpu[worker] || ($3 == cpu[worker] && $2 > rss[worker]))) worker = pid
			}
			END {
				if (worker) { focus = worker; role = "server-worker" }
				# Non-whitespace separators preserve absent measurements in Bash read.
				printf "%s|%s|%s|%s|%.0f|%s|%s\n", focus, rss[focus], cpu[focus], state[focus], total_rss,
					(samples ? sprintf("%.1f", total_cpu) : ""), role
			}
		'
}
