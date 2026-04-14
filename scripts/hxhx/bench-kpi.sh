#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
HXHX_BIN="${HXHX_BIN:-}"
HXHX_MACRO_HOST_BIN="${HXHX_MACRO_HOST_EXE:-}"
REPS="${HXHX_KPI_REPS:-3}"
RUN_MACRO_LANE="${HXHX_KPI_RUN_MACRO_LANE:-1}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="${HXHX_KPI_REPORT_DIR:-$ROOT/.hxhx/bench/kpi/$TIMESTAMP}"
WORK_DIR="$REPORT_DIR/work"
SAMPLES_TSV="$REPORT_DIR/samples.tsv"
REPORT_JSON="$REPORT_DIR/report.json"

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/bench-kpi.sh

Environment knobs:
  HAXE_BIN                       Haxe executable path (default: haxe)
  HXHX_BIN                       hxhx executable path (default: auto-build via scripts/hxhx/build-hxhx.sh)
  HXHX_MACRO_HOST_EXE            macro host executable path (default: auto-build when macro lane enabled)
  HXHX_KPI_REPS                  repetitions per KPI lane (default: 3)
  HXHX_KPI_RUN_MACRO_LANE        0/1 include macro-overhead KPI lane (default: 1)
  HXHX_KPI_REPORT_DIR            report directory (default: .hxhx/bench/kpi/<timestamp>)

Outputs:
  samples.tsv  (machine-readable samples)
  report.json  (stable summary schema: hxhx.kpi.v1 + lane ratio deltas)
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

is_positive_int() {
	case "$1" in
		''|*[!0-9]*)
			return 1
			;;
		*)
			[ "$1" -gt 0 ]
			;;
	esac
}

is_bool() {
	case "$1" in
		0|1)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

if ! is_positive_int "$REPS"; then
	echo "Invalid HXHX_KPI_REPS='$REPS' (expected positive integer)." >&2
	exit 2
fi

if ! is_bool "$RUN_MACRO_LANE"; then
	echo "Invalid HXHX_KPI_RUN_MACRO_LANE='$RUN_MACRO_LANE' (expected 0 or 1)." >&2
	exit 2
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "Missing python3 on PATH (required for KPI harness)." >&2
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "Missing node on PATH (required for native JS KPI lanes)." >&2
	exit 1
fi

if [ -z "$HXHX_BIN" ]; then
	HXHX_BIN="$(HAXE_BIN="$HAXE_BIN" bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ -z "$HXHX_BIN" ] || [ ! -x "$HXHX_BIN" ]; then
	echo "Missing hxhx binary (set HXHX_BIN or ensure build-hxhx.sh works)." >&2
	exit 1
fi

target_available() {
	local target="$1"
	local targets
	targets="$("$HXHX_BIN" --hxhx-list-targets 2>/dev/null || true)"
	printf '%s\n' "$targets" | grep -qx "$target"
}

if ! target_available "js"; then
	echo "hxhx binary does not expose native js lane (required for plugin/builtin KPI lanes)." >&2
	exit 1
fi

if [ "$RUN_MACRO_LANE" = "1" ]; then
	if [ -z "$HXHX_MACRO_HOST_BIN" ]; then
		HXHX_MACRO_HOST_BIN="$(bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
	fi
	if [ -z "$HXHX_MACRO_HOST_BIN" ] || [ ! -x "$HXHX_MACRO_HOST_BIN" ]; then
		echo "Missing hxhx macro host binary (set HXHX_MACRO_HOST_EXE or ensure build-hxhx-macro-host.sh works)." >&2
		exit 1
	fi
fi

mkdir -p "$WORK_DIR/src"
cat >"$WORK_DIR/src/Main.hx" <<'HX'
class Main {
	static function main() {
		var sum = 0;
		var xs = [1, 2, 3, 4];
		for (i in 0...xs.length) {
			sum += xs[i];
		}
		Sys.println("kpi=" + sum);
	}
}
HX

cat >"$WORK_DIR/src/KpiBenchMacros.hx" <<'HX'
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

class KpiBenchMacros {
	public static macro function init():Expr {
		Context.onAfterTyping(function(_) {});
		return macro null;
	}
}
HX

mkdir -p "$REPORT_DIR"
printf 'metric\tlane\trep\tvalue\n' >"$SAMPLES_TSV"

measure_command() {
	local command="$1"
	python3 - "$command" <<'PY'
import os
import resource
import subprocess
import sys
import time

command = sys.argv[1]
start = time.perf_counter()
proc = subprocess.run(["bash", "-lc", command], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
elapsed_ms = int((time.perf_counter() - start) * 1000)
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
rss_kb = int(rss / 1024) if rss > 10_000_000 else int(rss)
if proc.returncode != 0:
	print(proc.stdout, end="")
	sys.stderr.write(proc.stderr)
	sys.exit(proc.returncode)
print(f"{elapsed_ms}\t{rss_kb}")
PY
}

record_sample() {
	local metric="$1"
	local lane="$2"
	local rep="$3"
	local value="$4"
	printf '%s\t%s\t%s\t%s\n' "$metric" "$lane" "$rep" "$value" >>"$SAMPLES_TSV"
}

run_compile_lane() {
	local lane="$1"
	local command="$2"
	local rep
	for rep in $(seq 1 "$REPS"); do
		local measured wall_ms rss_kb
		measured="$(measure_command "$command")"
		IFS=$'\t' read -r wall_ms rss_kb <<<"$measured"
		record_sample "compile_wall_ms" "$lane" "$rep" "$wall_ms"
		record_sample "peak_rss_kb" "$lane" "$rep" "$rss_kb"
	done
}

run_incremental_lane() {
	local lane="$1"
	local command="$2"
	local rep
	for rep in $(seq 1 "$REPS"); do
		measure_command "$command" >/dev/null
		local measured wall_ms rss_kb
		measured="$(measure_command "$command")"
		IFS=$'\t' read -r wall_ms rss_kb <<<"$measured"
		record_sample "incremental_rebuild_ms" "$lane" "$rep" "$wall_ms"
	done
}

run_macro_overhead_lane() {
	local lane="$1"
	local baseline_command="$2"
	local macro_command="$3"
	local rep
	for rep in $(seq 1 "$REPS"); do
		local baseline_measured macro_measured base_ms macro_ms base_rss macro_rss overhead
		baseline_measured="$(measure_command "$baseline_command")"
		macro_measured="$(measure_command "$macro_command")"
		IFS=$'\t' read -r base_ms base_rss <<<"$baseline_measured"
		IFS=$'\t' read -r macro_ms macro_rss <<<"$macro_measured"
		overhead=$((macro_ms - base_ms))
		if [ "$overhead" -lt 0 ]; then
			overhead=0
		fi
		record_sample "macro_baseline_compile_ms" "$lane" "$rep" "$base_ms"
		record_sample "macro_enabled_compile_ms" "$lane" "$rep" "$macro_ms"
		record_sample "macro_overhead_ms" "$lane" "$rep" "$overhead"
		record_sample "macro_peak_rss_kb" "$lane" "$rep" "$macro_rss"
	done
}

portable_cmd="\"$HXHX_BIN\" --ocaml --hxhx-no-emit -cp \"$WORK_DIR/src\" -main Main --hxhx-out \"$WORK_DIR/out_ocaml_portable\" -D ocaml_profile=portable"
metal_cmd="\"$HXHX_BIN\" --ocaml --hxhx-no-emit -cp \"$WORK_DIR/src\" -main Main --hxhx-out \"$WORK_DIR/out_ocaml_metal\" -D ocaml_profile=metal"
builtin_js_cmd="\"$HXHX_BIN\" --js \"$WORK_DIR/out_js_builtin/main.js\" --hxhx-no-run -cp \"$WORK_DIR/src\" -main Main --hxhx-out \"$WORK_DIR/out_js_builtin\""
plugin_js_cmd="\"$HXHX_BIN\" --js \"$WORK_DIR/out_js_plugin/main.js\" --hxhx-no-run -cp \"$WORK_DIR/src\" -main Main --hxhx-out \"$WORK_DIR/out_js_plugin\" -D hxhx_backend_provider=backend.js.JsBackend"
upstream_cmd="\"$HAXE_BIN\" --no-output -cp \"$WORK_DIR/src\" -main Main"

echo "== hxhx KPI harness"
echo "HAXE_BIN: $HAXE_BIN"
echo "HXHX_BIN: $HXHX_BIN"
echo "REPS: $REPS"
echo "RUN_MACRO_LANE: $RUN_MACRO_LANE"
echo "REPORT_DIR: $REPORT_DIR"
echo ""

run_compile_lane "ocaml_portable_builtin" "$portable_cmd"
run_compile_lane "ocaml_metal_builtin" "$metal_cmd"
run_compile_lane "upstream_haxe" "$upstream_cmd"
run_compile_lane "js_builtin" "$builtin_js_cmd"
run_compile_lane "js_provider" "$plugin_js_cmd"

run_incremental_lane "ocaml_portable_builtin" "$portable_cmd"
run_incremental_lane "ocaml_metal_builtin" "$metal_cmd"
run_incremental_lane "upstream_haxe" "$upstream_cmd"

if [ "$RUN_MACRO_LANE" = "1" ]; then
	upstream_macro_base_cmd="\"$HAXE_BIN\" --no-output -cp \"$WORK_DIR/src\" -main Main"
	upstream_macro_enabled_cmd="\"$HAXE_BIN\" --no-output -cp \"$WORK_DIR/src\" --macro 'KpiBenchMacros.init()' -main Main"
	run_macro_overhead_lane "upstream_haxe" "$upstream_macro_base_cmd" "$upstream_macro_enabled_cmd"

	macro_base_portable_cmd="\"$HXHX_BIN\" --ocaml --hxhx-no-emit -cp \"$WORK_DIR/src\" -main Main --hxhx-out \"$WORK_DIR/out_macro_portable_base\" -D ocaml_profile=portable"
	macro_enabled_portable_cmd="HXHX_MACRO_HOST_EXE=\"$HXHX_MACRO_HOST_BIN\" \"$HXHX_BIN\" --ocaml --hxhx-no-emit -cp \"$WORK_DIR/src\" --macro 'KpiBenchMacros.init()' -main Main --hxhx-out \"$WORK_DIR/out_macro_portable_enabled\" -D ocaml_profile=portable"
	run_macro_overhead_lane "ocaml_portable_builtin" "$macro_base_portable_cmd" "$macro_enabled_portable_cmd"

	macro_base_metal_cmd="\"$HXHX_BIN\" --ocaml --hxhx-no-emit -cp \"$WORK_DIR/src\" -main Main --hxhx-out \"$WORK_DIR/out_macro_metal_base\" -D ocaml_profile=metal"
	macro_enabled_metal_cmd="HXHX_MACRO_HOST_EXE=\"$HXHX_MACRO_HOST_BIN\" \"$HXHX_BIN\" --ocaml --hxhx-no-emit -cp \"$WORK_DIR/src\" --macro 'KpiBenchMacros.init()' -main Main --hxhx-out \"$WORK_DIR/out_macro_metal_enabled\" -D ocaml_profile=metal"
	run_macro_overhead_lane "ocaml_metal_builtin" "$macro_base_metal_cmd" "$macro_enabled_metal_cmd"
fi

python3 - "$SAMPLES_TSV" "$REPORT_JSON" "$REPS" "$HAXE_BIN" "$HXHX_BIN" "$RUN_MACRO_LANE" "$ROOT" <<'PY'
import csv
import json
import math
import platform
import statistics
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone

samples_path, report_path, reps, haxe_bin, hxhx_bin, run_macro_lane, repo_root = sys.argv[1:]
groups = defaultdict(list)
with open(samples_path, newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    for row in reader:
        metric = row["metric"]
        lane = row["lane"]
        value = int(row["value"])
        groups[(metric, lane)].append(value)

def p95(values):
    if not values:
        return 0
    ordered = sorted(values)
    idx = max(0, min(len(ordered) - 1, math.ceil(0.95 * len(ordered)) - 1))
    return int(ordered[idx])

def summarize(values):
    ordered = sorted(values)
    return {
        "count": len(values),
        "min": int(ordered[0]),
        "max": int(ordered[-1]),
        "mean": round(float(statistics.fmean(values)), 3),
        "median": int(statistics.median(values)),
        "p95": p95(values),
        "samples": [int(v) for v in values],
    }

def unit_for(metric):
    if metric.endswith("_kb"):
        return "kb"
    return "ms"

def ratio(numerator, denominator):
    if denominator == 0:
        return None
    return round(float(numerator) / float(denominator), 4)

def metric_median(metric, lane):
    values = groups.get((metric, lane))
    if not values:
        return None
    return int(statistics.median(values))

ratio_specs = [
    ("portable_over_metal", "ocaml_portable_builtin", "ocaml_metal_builtin"),
    ("portable_over_upstream", "ocaml_portable_builtin", "upstream_haxe"),
    ("metal_over_upstream", "ocaml_metal_builtin", "upstream_haxe"),
]

tracked_metrics = [
    "compile_wall_ms",
    "peak_rss_kb",
    "incremental_rebuild_ms",
]
if run_macro_lane == "1":
    tracked_metrics.extend(
        [
            "macro_baseline_compile_ms",
            "macro_enabled_compile_ms",
            "macro_overhead_ms",
            "macro_peak_rss_kb",
        ]
    )

lane_ratios = []
for ratio_name, numerator_lane, denominator_lane in ratio_specs:
    metric_ratios = {}
    has_any_ratio = False
    for metric in tracked_metrics:
        numerator = metric_median(metric, numerator_lane)
        denominator = metric_median(metric, denominator_lane)
        value = None if numerator is None or denominator is None else ratio(numerator, denominator)
        metric_ratios[metric] = value
        if value is not None:
            has_any_ratio = True
    if has_any_ratio:
        lane_ratios.append(
            {
                "name": ratio_name,
                "numerator_lane": numerator_lane,
                "denominator_lane": denominator_lane,
                "metrics": metric_ratios,
            }
        )

haxe_version = "unknown"
try:
    proc = subprocess.run([haxe_bin, "--version"], check=False, capture_output=True, text=True)
    if proc.returncode == 0:
        haxe_version = proc.stdout.strip() or proc.stderr.strip() or "unknown"
except Exception:
    pass

def normalize_path(path):
    if not path:
        return path
    prefix = repo_root.rstrip("/") + "/"
    if path.startswith(prefix):
        return path[len(prefix):]
    return path

report = {
    "schema": "hxhx.kpi.v1",
    "generated_at_utc": datetime.now(timezone.utc).isoformat(),
    "config": {
        "reps": int(reps),
        "run_macro_lane": run_macro_lane == "1",
    },
    "environment": {
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "haxe_bin": haxe_bin,
        "haxe_version": haxe_version,
        "hxhx_bin": normalize_path(hxhx_bin),
    },
    "metrics": [],
    "lane_ratios": lane_ratios,
}

for (metric, lane) in sorted(groups.keys()):
    values = groups[(metric, lane)]
    report["metrics"].append(
        {
            "metric": metric,
            "lane": lane,
            "unit": unit_for(metric),
            "summary": summarize(values),
        }
    )

with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("== KPI summary")
for entry in report["metrics"]:
    summary = entry["summary"]
    print(
        f"{entry['metric']:30s} lane={entry['lane']:26s} "
        f"median={summary['median']:6d}{entry['unit']} "
        f"p95={summary['p95']:6d}{entry['unit']} "
        f"mean={summary['mean']}"
    )

if lane_ratios:
    print("== KPI lane ratios (median-based)")
    for ratio_entry in lane_ratios:
        ratio_values = []
        for metric in tracked_metrics:
            metric_ratio = ratio_entry["metrics"].get(metric)
            if metric_ratio is None:
                continue
            ratio_values.append(f"{metric}={metric_ratio}")
        if ratio_values:
            print(
                f"{ratio_entry['name']}: "
                + ", ".join(ratio_values)
            )
PY

echo ""
echo "KPI_SAMPLES_TSV=$SAMPLES_TSV"
echo "KPI_REPORT_JSON=$REPORT_JSON"
