#!/usr/bin/env bash
set -euo pipefail

# Regenerate the committed bootstrap snapshot for `hxhx` itself.
#
# Why
# - CI/Gate runners should be able to build `hxhx` without requiring a stage0 `haxe` binary.
# - We achieve this by committing a generated OCaml snapshot under `packages/hxhx/bootstrap_out`
#   and building it with `dune`.
#
# What
# - Emits `packages/hxhx` via stage0 `haxe` + `reflaxe.ocaml` (emit-only; no dune build).
# - Copies the generated OCaml sources (excluding `_build/` and `_gen_hx/`) into:
#     packages/hxhx/bootstrap_out/
# - Automatically shards oversized generated OCaml units into deterministic
#   `<Module>.ml.partNNN` chunk files + `<Module>.ml.parts` manifests to avoid tracked files above
#   GitHub's 50MB warning threshold.
#
# Notes
# - Maintainer-only script: it requires stage0 `haxe`.
# - Do not edit files inside `packages/hxhx/bootstrap_out/` by hand.

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/regenerate-hxhx-bootstrap.sh [options]

Options:
  --fast                     Local iteration mode. Defaults to incremental emit and skips snapshot verify.
  --full                     Full deterministic mode (default): clean emit output and verify snapshot build.
  --incremental              Reuse existing packages/hxhx/out before stage0 emit (faster local loop).
  --clean-out                Clean packages/hxhx/out before stage0 emit.
  --no-verify                Skip bootstrap snapshot verify build.
  --verify                   Run bootstrap snapshot verify build.
  --server-preflight         Check for stale haxe --wait/--server-connect processes before emit (default).
  --no-server-preflight      Skip stale haxe server preflight checks.
  --kill-repo-server         Stop only the repo-owned haxe --wait server before emit.
  --kill-all-haxe-servers    Stop all local haxe --wait/--server-connect processes before emit (unsafe).
  --kill-stale-haxe-servers  Deprecated alias for --kill-all-haxe-servers.
  --use-repo-server          Start/reuse repo-owned haxe --wait server and pass --connect.
  --keep-repo-server         Keep repo-owned server alive after this run (implies --use-repo-server).
  --skip-if-unchanged        Skip stage0 emit when fingerprint matches previous successful regen.
  --force                    Ignore fingerprint match and force stage0 emit.
  --profile                  Enable stage0 `--times` and per-filter timing (`-D filter-times`).
  --stage0-no-opt            Add `--no-opt` to stage0 haxe compile (lower memory, slower output).
  --stage0-opt               Disable stage0 `--no-opt` override.
  --stage0-no-inline         Add `--no-inline` to stage0 haxe compile (lower peak RSS; slower builds).
  --stage0-inline            Disable stage0 `--no-inline` override.
  --stage0-no-native-parser  Add `-D hxhx_stage0_no_native_parser` (force pure-Haxe parser path in stage0 build).
  --stage0-native-parser     Disable stage0 no-native-parser override.
  --stage0-no-hx-parser      Add `-D hxhx_stage0_no_hx_parser` (trim pure-Haxe parser fallbacks in stage0 profiling lane).
  --stage0-hx-parser         Disable stage0 no-hx-parser override.
  --stage0-no-expr-macros    Add `-D hxhx_stage0_no_expr_macros` (trim Stage3 expression-macro expander path in stage0 compile graph).
  --stage0-expr-macros       Disable stage0 no-expr-macros override.
  --stage0-no-external-macro-host
                             Add `-D hxhx_stage0_no_external_macro_host` (trim external macro-host runtime paths in stage0 compile graph).
  --stage0-external-macro-host
                             Disable stage0 no-external-macro-host override.
  --stage0-no-stage3         Add `-D hxhx_stage0_no_stage3` (trim Stage3 native lane paths in stage0 compile graph).
  --stage0-stage3            Disable stage0 no-stage3 override.
  --stage0-no-internal-tools Add `-D hxhx_stage0_no_internal_tools` (trim internal bring-up CLI paths in stage0 compile graph).
  --stage0-internal-tools    Disable stage0 no-internal-tools override.
  --stage0-no-source-normalize-extract
                            Add `-D hxhx_stage0_no_source_normalize_extract` (inline HxParser normalization helpers for stage0 A/B only).
  --stage0-source-normalize-extract
                            Disable stage0 no-source-normalize-extract override.
  --stage0-ocaml-only        Add `-D hxhx_stage0_ocaml_only` (exclude linked js-native backend from stage0 compile graph).
  --stage0-with-js           Disable stage0 ocaml-only define (default behavior).
  --stage0-no-line-directives
                             Add `-D ocaml_no_line_directives` (reduce generated output metadata in stage0 emit).
  --stage0-line-directives   Disable stage0 no-line-directives override (default behavior).
  --stage0-ocamlrunparam <value>
                             Set OCAMLRUNPARAM for stage0 haxe process only (e.g. s=4M).
  --report-json <path>       Write a machine-readable timing summary JSON.
  --diag-every <seconds>     When heartbeat is disabled, print periodic stage0 diagnostics.
  --stage0-haxe-policy <mode>
                             Stage0 haxe binary policy: warn | prefer-native | require-native.
  --stage0-native-haxe-bin <path>
                             Explicit native stage0 haxe candidate (used by prefer/require-native).
  --stage0-selection-only    Resolve/log stage0 haxe selection and exit before emit/copy/verify.
  -h, --help                 Show this help.

Environment knobs (all optional):
  HXHX_BOOTSTRAP_FAST=1             Same effect as --fast.
  HXHX_BOOTSTRAP_CLEAN_OUT=0        Reuse packages/hxhx/out (incremental).
  HXHX_BOOTSTRAP_VERIFY=0           Skip verify step.
  HXHX_HAXE_SERVER_PREFLIGHT=1      Enable stale haxe server preflight.
  HXHX_KILL_STALE_HAXE_SERVERS=1    Kill all local haxe servers in preflight (unsafe).
  HXHX_KILL_REPO_HAXE_SERVER=1      Kill only repo-owned haxe server in preflight.
  HXHX_BOOTSTRAP_USE_REPO_SERVER=1  Use repo-owned haxe --wait server.
  HXHX_BOOTSTRAP_KEEP_REPO_SERVER=1 Keep repo-owned server alive after run.
  HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED=1  Enable fingerprint skip.
  HXHX_BOOTSTRAP_FORCE=1            Force emit even when fingerprint matches.
  HXHX_BOOTSTRAP_PROFILE=1          Enable `--times` + `-D filter-times`.
  HXHX_STAGE0_NO_OPT=1              Add `--no-opt` to stage0 haxe compile.
  HXHX_STAGE0_NO_INLINE=1           Add `--no-inline` to stage0 haxe compile.
  HXHX_STAGE0_NO_NATIVE_PARSER=1    Add `-D hxhx_stage0_no_native_parser` for stage0 emit.
  HXHX_STAGE0_NO_HX_PARSER=1        Add `-D hxhx_stage0_no_hx_parser` for stage0 emit.
  HXHX_STAGE0_NO_EXPR_MACROS=1      Add `-D hxhx_stage0_no_expr_macros` for stage0 emit.
  HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST=1
                                     Add `-D hxhx_stage0_no_external_macro_host` for stage0 emit.
  HXHX_STAGE0_NO_STAGE3=1            Add `-D hxhx_stage0_no_stage3` for stage0 emit.
  HXHX_STAGE0_NO_INTERNAL_TOOLS=1    Add `-D hxhx_stage0_no_internal_tools` for stage0 emit.
  HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT=1
                                     Add `-D hxhx_stage0_no_source_normalize_extract` for stage0 emit.
  HXHX_STAGE0_OCAML_ONLY=1          Add `-D hxhx_stage0_ocaml_only` for stage0 emit.
  HXHX_STAGE0_NO_LINE_DIRECTIVES=1  Add `-D ocaml_no_line_directives` for stage0 emit.
  HXHX_STAGE0_OCAMLRUNPARAM=s=4M    Set OCAMLRUNPARAM for stage0 haxe process only.
  HXHX_BOOTSTRAP_REPORT_JSON=<path> Same as --report-json.
  HXHX_STAGE0_DIAG_EVERY=30         Diagnostics cadence when heartbeat is disabled.
  HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native
                                    Stage0 haxe binary policy for bootstrap regen.
  HXHX_STAGE0_NATIVE_HAXE_BIN=/abs/path/to/haxe
                                    Explicit native stage0 haxe candidate.
  HXHX_STAGE0_SELECTION_ONLY=1      Resolve/log stage0 haxe selection and exit early.
  HXHX_DUNE_JOBS=4                  Force dune worker count (auto by default).
USAGE
}

assert_bool_01() {
	local name="$1"
	local value="$2"
	case "$value" in
		0|1) ;;
		*)
			echo "Invalid value for $name: '$value' (expected 0 or 1)." >&2
			exit 1
			;;
	esac
}

assert_non_negative_int() {
	local name="$1"
	local value="$2"
	case "$value" in
		''|*[!0-9]*)
			echo "Invalid value for $name: '$value' (expected a non-negative integer)." >&2
			exit 1
			;;
		*)
			;;
	esac
}

assert_stage0_haxe_policy() {
	local value="$1"
	case "$value" in
		warn|prefer-native|require-native) ;;
		*)
			echo "Invalid HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY: '$value' (expected warn|prefer-native|require-native)." >&2
			exit 1
			;;
	esac
}

assert_dune_jobs() {
	local value="$1"
	case "$value" in
		auto) ;;
		''|*[!0-9]*|0)
			echo "Invalid HXHX_DUNE_JOBS: '$value' (expected auto or a positive integer)." >&2
			exit 1
			;;
	esac
}

now_ts() {
	date +%s
}

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_CONNECT="${HAXE_CONNECT:-}"
HXHX_BOOTSTRAP_DEBUG="${HXHX_BOOTSTRAP_DEBUG:-0}"
HXHX_STAGE0_PROGRESS="${HXHX_STAGE0_PROGRESS:-0}"
HXHX_STAGE0_TELEMETRY="${HXHX_STAGE0_TELEMETRY:-0}"
HXHX_STAGE0_TELEMETRY_DETAIL="${HXHX_STAGE0_TELEMETRY_DETAIL:-0}"
HXHX_STAGE0_TELEMETRY_CLASS="${HXHX_STAGE0_TELEMETRY_CLASS:-}"
HXHX_STAGE0_TELEMETRY_FIELD="${HXHX_STAGE0_TELEMETRY_FIELD:-}"
HXHX_STAGE0_VERBOSE="${HXHX_STAGE0_VERBOSE:-0}"
HXHX_STAGE0_DISABLE_PREPASSES="${HXHX_STAGE0_DISABLE_PREPASSES:-0}"
HXHX_STAGE0_NO_OPT="${HXHX_STAGE0_NO_OPT:-0}"
HXHX_STAGE0_NO_INLINE="${HXHX_STAGE0_NO_INLINE:-0}"
HXHX_STAGE0_NO_NATIVE_PARSER="${HXHX_STAGE0_NO_NATIVE_PARSER:-0}"
HXHX_STAGE0_NO_HX_PARSER="${HXHX_STAGE0_NO_HX_PARSER:-0}"
HXHX_STAGE0_NO_EXPR_MACROS="${HXHX_STAGE0_NO_EXPR_MACROS:-0}"
HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST="${HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST:-0}"
HXHX_STAGE0_NO_STAGE3="${HXHX_STAGE0_NO_STAGE3:-0}"
HXHX_STAGE0_NO_INTERNAL_TOOLS="${HXHX_STAGE0_NO_INTERNAL_TOOLS:-0}"
HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT="${HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT:-0}"
HXHX_STAGE0_OCAML_ONLY="${HXHX_STAGE0_OCAML_ONLY:-0}"
HXHX_STAGE0_NO_LINE_DIRECTIVES="${HXHX_STAGE0_NO_LINE_DIRECTIVES:-0}"
HXHX_STAGE0_OCAMLRUNPARAM="${HXHX_STAGE0_OCAMLRUNPARAM:-}"
HXHX_STAGE0_HEARTBEAT="${HXHX_STAGE0_HEARTBEAT:-20}"
HXHX_STAGE0_LOG_TAIL_LINES="${HXHX_STAGE0_LOG_TAIL_LINES:-80}"
HXHX_STAGE0_FAILFAST_SECS="${HXHX_STAGE0_FAILFAST_SECS:-900}"
HXHX_STAGE0_HEARTBEAT_TAIL_LINES="${HXHX_STAGE0_HEARTBEAT_TAIL_LINES:-0}"
HXHX_KEEP_LOGS="${HXHX_KEEP_LOGS:-0}"
HXHX_LOG_DIR="${HXHX_LOG_DIR:-}"
HXHX_BOOTSTRAP_FAST="${HXHX_BOOTSTRAP_FAST:-0}"
HXHX_BOOTSTRAP_CLEAN_OUT="${HXHX_BOOTSTRAP_CLEAN_OUT:-}"
HXHX_BOOTSTRAP_VERIFY="${HXHX_BOOTSTRAP_VERIFY:-}"
HXHX_HAXE_SERVER_PREFLIGHT="${HXHX_HAXE_SERVER_PREFLIGHT:-1}"
HXHX_KILL_STALE_HAXE_SERVERS="${HXHX_KILL_STALE_HAXE_SERVERS:-0}"
HXHX_KILL_REPO_HAXE_SERVER="${HXHX_KILL_REPO_HAXE_SERVER:-0}"
HXHX_STAGE0_DIAG_EVERY="${HXHX_STAGE0_DIAG_EVERY:-0}"
HXHX_BOOTSTRAP_USE_REPO_SERVER="${HXHX_BOOTSTRAP_USE_REPO_SERVER:-0}"
HXHX_BOOTSTRAP_KEEP_REPO_SERVER="${HXHX_BOOTSTRAP_KEEP_REPO_SERVER:-0}"
HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED="${HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED:-0}"
HXHX_BOOTSTRAP_FORCE="${HXHX_BOOTSTRAP_FORCE:-0}"
HXHX_BOOTSTRAP_PROFILE="${HXHX_BOOTSTRAP_PROFILE:-0}"
HXHX_BOOTSTRAP_REPORT_JSON="${HXHX_BOOTSTRAP_REPORT_JSON:-}"
HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY="${HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY:-prefer-native}"
HXHX_STAGE0_NATIVE_HAXE_BIN="${HXHX_STAGE0_NATIVE_HAXE_BIN:-}"
HXHX_STAGE0_SELECTION_ONLY="${HXHX_STAGE0_SELECTION_ONLY:-0}"
HXHX_DUNE_JOBS="${HXHX_DUNE_JOBS:-auto}"

used_deprecated_kill_flag=0
while [ $# -gt 0 ]; do
	case "$1" in
		--fast)
			HXHX_BOOTSTRAP_FAST=1
			;;
		--full)
			HXHX_BOOTSTRAP_FAST=0
			;;
		--incremental)
			HXHX_BOOTSTRAP_CLEAN_OUT=0
			;;
		--clean-out)
			HXHX_BOOTSTRAP_CLEAN_OUT=1
			;;
		--no-verify)
			HXHX_BOOTSTRAP_VERIFY=0
			;;
		--verify)
			HXHX_BOOTSTRAP_VERIFY=1
			;;
		--server-preflight)
			HXHX_HAXE_SERVER_PREFLIGHT=1
			;;
		--no-server-preflight)
			HXHX_HAXE_SERVER_PREFLIGHT=0
			;;
		--kill-repo-server)
			HXHX_KILL_REPO_HAXE_SERVER=1
			;;
		--kill-all-haxe-servers)
			HXHX_KILL_STALE_HAXE_SERVERS=1
			;;
		--kill-stale-haxe-servers)
			HXHX_KILL_STALE_HAXE_SERVERS=1
			used_deprecated_kill_flag=1
			;;
		--use-repo-server)
			HXHX_BOOTSTRAP_USE_REPO_SERVER=1
			;;
		--keep-repo-server)
			HXHX_BOOTSTRAP_USE_REPO_SERVER=1
			HXHX_BOOTSTRAP_KEEP_REPO_SERVER=1
			;;
		--skip-if-unchanged)
			HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED=1
			;;
		--force)
			HXHX_BOOTSTRAP_FORCE=1
			;;
		--profile)
			HXHX_BOOTSTRAP_PROFILE=1
			;;
		--stage0-no-opt)
			HXHX_STAGE0_NO_OPT=1
			;;
		--stage0-opt)
			HXHX_STAGE0_NO_OPT=0
			;;
		--stage0-no-inline)
			HXHX_STAGE0_NO_INLINE=1
			;;
		--stage0-inline)
			HXHX_STAGE0_NO_INLINE=0
			;;
		--stage0-no-native-parser)
			HXHX_STAGE0_NO_NATIVE_PARSER=1
			;;
		--stage0-native-parser)
			HXHX_STAGE0_NO_NATIVE_PARSER=0
			;;
		--stage0-no-hx-parser)
			HXHX_STAGE0_NO_HX_PARSER=1
			;;
		--stage0-hx-parser)
			HXHX_STAGE0_NO_HX_PARSER=0
			;;
		--stage0-no-expr-macros)
			HXHX_STAGE0_NO_EXPR_MACROS=1
			;;
		--stage0-expr-macros)
			HXHX_STAGE0_NO_EXPR_MACROS=0
			;;
		--stage0-no-external-macro-host)
			HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST=1
			;;
		--stage0-external-macro-host)
			HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST=0
			;;
		--stage0-no-stage3)
			HXHX_STAGE0_NO_STAGE3=1
			;;
		--stage0-stage3)
			HXHX_STAGE0_NO_STAGE3=0
			;;
		--stage0-no-internal-tools)
			HXHX_STAGE0_NO_INTERNAL_TOOLS=1
			;;
		--stage0-internal-tools)
			HXHX_STAGE0_NO_INTERNAL_TOOLS=0
			;;
		--stage0-no-source-normalize-extract)
			HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT=1
			;;
		--stage0-source-normalize-extract)
			HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT=0
			;;
		--stage0-ocaml-only)
			HXHX_STAGE0_OCAML_ONLY=1
			;;
		--stage0-with-js)
			HXHX_STAGE0_OCAML_ONLY=0
			;;
		--stage0-no-line-directives)
			HXHX_STAGE0_NO_LINE_DIRECTIVES=1
			;;
		--stage0-line-directives)
			HXHX_STAGE0_NO_LINE_DIRECTIVES=0
			;;
		--stage0-ocamlrunparam)
			shift
			if [ $# -eq 0 ]; then
				echo "Missing value for --stage0-ocamlrunparam" >&2
				exit 1
			fi
			HXHX_STAGE0_OCAMLRUNPARAM="$1"
			;;
		--report-json)
			shift
			if [ $# -eq 0 ]; then
				echo "Missing value for --report-json" >&2
				exit 1
			fi
			HXHX_BOOTSTRAP_REPORT_JSON="$1"
			;;
		--diag-every)
			shift
			if [ $# -eq 0 ]; then
				echo "Missing value for --diag-every" >&2
				exit 1
			fi
				HXHX_STAGE0_DIAG_EVERY="$1"
				;;
		--stage0-haxe-policy)
			shift
			if [ $# -eq 0 ]; then
				echo "Missing value for --stage0-haxe-policy" >&2
				exit 1
			fi
			HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY="$1"
			;;
		--stage0-native-haxe-bin)
			shift
			if [ $# -eq 0 ]; then
				echo "Missing value for --stage0-native-haxe-bin" >&2
				exit 1
			fi
				HXHX_STAGE0_NATIVE_HAXE_BIN="$1"
				;;
		--stage0-selection-only)
			HXHX_STAGE0_SELECTION_ONLY=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
	shift
done

assert_bool_01 "HXHX_BOOTSTRAP_FAST" "$HXHX_BOOTSTRAP_FAST"
if [ -z "$HXHX_BOOTSTRAP_CLEAN_OUT" ]; then
	HXHX_BOOTSTRAP_CLEAN_OUT="$([ "$HXHX_BOOTSTRAP_FAST" = "1" ] && echo 0 || echo 1)"
fi
if [ -z "$HXHX_BOOTSTRAP_VERIFY" ]; then
	HXHX_BOOTSTRAP_VERIFY="$([ "$HXHX_BOOTSTRAP_FAST" = "1" ] && echo 0 || echo 1)"
fi
assert_bool_01 "HXHX_BOOTSTRAP_CLEAN_OUT" "$HXHX_BOOTSTRAP_CLEAN_OUT"
assert_bool_01 "HXHX_BOOTSTRAP_VERIFY" "$HXHX_BOOTSTRAP_VERIFY"
assert_bool_01 "HXHX_HAXE_SERVER_PREFLIGHT" "$HXHX_HAXE_SERVER_PREFLIGHT"
assert_bool_01 "HXHX_KILL_STALE_HAXE_SERVERS" "$HXHX_KILL_STALE_HAXE_SERVERS"
assert_bool_01 "HXHX_KILL_REPO_HAXE_SERVER" "$HXHX_KILL_REPO_HAXE_SERVER"
assert_bool_01 "HXHX_BOOTSTRAP_USE_REPO_SERVER" "$HXHX_BOOTSTRAP_USE_REPO_SERVER"
assert_bool_01 "HXHX_BOOTSTRAP_KEEP_REPO_SERVER" "$HXHX_BOOTSTRAP_KEEP_REPO_SERVER"
assert_bool_01 "HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED" "$HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED"
assert_bool_01 "HXHX_BOOTSTRAP_FORCE" "$HXHX_BOOTSTRAP_FORCE"
assert_bool_01 "HXHX_BOOTSTRAP_PROFILE" "$HXHX_BOOTSTRAP_PROFILE"
assert_bool_01 "HXHX_STAGE0_NO_OPT" "$HXHX_STAGE0_NO_OPT"
assert_bool_01 "HXHX_STAGE0_NO_INLINE" "$HXHX_STAGE0_NO_INLINE"
assert_bool_01 "HXHX_STAGE0_NO_NATIVE_PARSER" "$HXHX_STAGE0_NO_NATIVE_PARSER"
assert_bool_01 "HXHX_STAGE0_NO_HX_PARSER" "$HXHX_STAGE0_NO_HX_PARSER"
assert_bool_01 "HXHX_STAGE0_NO_EXPR_MACROS" "$HXHX_STAGE0_NO_EXPR_MACROS"
assert_bool_01 "HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST" "$HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST"
assert_bool_01 "HXHX_STAGE0_NO_STAGE3" "$HXHX_STAGE0_NO_STAGE3"
assert_bool_01 "HXHX_STAGE0_NO_INTERNAL_TOOLS" "$HXHX_STAGE0_NO_INTERNAL_TOOLS"
assert_bool_01 "HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT" "$HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT"
assert_bool_01 "HXHX_STAGE0_OCAML_ONLY" "$HXHX_STAGE0_OCAML_ONLY"
assert_bool_01 "HXHX_STAGE0_NO_LINE_DIRECTIVES" "$HXHX_STAGE0_NO_LINE_DIRECTIVES"
	assert_bool_01 "HXHX_STAGE0_SELECTION_ONLY" "$HXHX_STAGE0_SELECTION_ONLY"
	assert_non_negative_int "HXHX_STAGE0_DIAG_EVERY" "$HXHX_STAGE0_DIAG_EVERY"
	assert_stage0_haxe_policy "$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY"
	assert_dune_jobs "$HXHX_DUNE_JOBS"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="$ROOT/packages/hxhx"
OUT_DIR="$PKG_DIR/out"
BOOTSTRAP_DIR="$PKG_DIR/bootstrap_out"
BOOTSTRAP_VERIFY_DIR="${HXHX_BOOTSTRAP_VERIFY_DIR:-$PKG_DIR/bootstrap_verify}"
STATE_DIR="${HXHX_STATE_DIR:-$ROOT/.hxhx/state}"
FINGERPRINT_FILE="$STATE_DIR/bootstrap_regen_fingerprint.v1"
HAXE_SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"

phase_preflight_sec=0
phase_emit_sec=0
phase_copy_sec=0
phase_shard_sec=0
phase_verify_sec=0
total_sec=0
total_start=0
skipped_emit=0
stage0_heartbeat_samples=0
stage0_heartbeat_peak_rss_mb=0
script_status="ok"
script_exit_code=0
script_report_written=0
stage0_haxe_requested="$HAXE_BIN"
stage0_haxe_resolved=""
stage0_haxe_mode="unknown"
stage0_haxe_file_desc="unknown"
stage0_haxe_version=""
stage0_haxe_native_candidate=""
stage0_haxe_switched=0
resolved_haxe_connect="$HAXE_CONNECT"
repo_server_started_here=0
repo_server_was_running=0
current_fingerprint=""

ensure_state_dir() {
	mkdir -p "$STATE_DIR"
}

create_stage0_log_file() {
	local prefix="$1"
	local template=""
	if [ -n "$HXHX_LOG_DIR" ]; then
		mkdir -p "$HXHX_LOG_DIR"
		template="${HXHX_LOG_DIR%/}/${prefix}.XXXXXX"
	else
		template="${TMPDIR:-/tmp}/${prefix}.XXXXXX"
	fi
	mktemp "$template"
}

cleanup_stage0_log_file() {
	local path="$1"
	if [ -z "$path" ] || [ ! -f "$path" ]; then
		return
	fi
	if [ "$HXHX_KEEP_LOGS" = "1" ]; then
		echo "== Stage0 emit log retained: $path"
	else
		rm -f "$path"
	fi
}

list_haxe_server_pids() {
	ps -axo pid=,command= | awk '
		{
			pid = $1
			$1 = ""
			cmd = substr($0, 2)
			if (cmd ~ /haxe/ && (cmd ~ /--wait([[:space:]]|$)/ || cmd ~ /--server-connect([[:space:]]|$)/))
				print pid
		}
	' | sort -u
}

print_haxe_server_processes() {
	local pids="$1"
	if [ -z "$pids" ]; then
		return
	fi
	local ps_pids
	ps_pids="$(printf '%s\n' "$pids" | paste -sd, -)"
	if [ -z "$ps_pids" ]; then
		return
	fi
	ps -o pid=,etime=,rss=,command= -p "$ps_pids" 2>/dev/null || true
}

kill_all_haxe_servers() {
	local pids
	pids="$(list_haxe_server_pids)"
	if [ -z "$pids" ]; then
		echo "== Haxe server preflight: no local haxe server processes found"
		return
	fi

	local count
	count="$(printf '%s\n' "$pids" | sed '/^$/d' | wc -l | tr -d ' ')"
	echo "== Haxe server preflight: found $count local haxe server process(es):"
	print_haxe_server_processes "$pids"
	echo "== Haxe server preflight: terminating all local haxe server process(es)"
	# shellcheck disable=SC2086
	kill $pids >/dev/null 2>&1 || true
	sleep 1

	local remaining
	remaining="$(list_haxe_server_pids)"
	if [ -n "$remaining" ]; then
		echo "== Haxe server preflight: forcing kill for remaining process(es)"
		# shellcheck disable=SC2086
		kill -9 $remaining >/dev/null 2>&1 || true
		sleep 1
	fi

	local after
	after="$(list_haxe_server_pids)"
	if [ -n "$after" ]; then
		local after_count
		after_count="$(printf '%s\n' "$after" | sed '/^$/d' | wc -l | tr -d ' ')"
		echo "== Haxe server preflight: warning - $after_count process(es) still present after cleanup attempt:"
		print_haxe_server_processes "$after"
	else
		echo "== Haxe server preflight: global haxe server cleanup complete"
	fi
}

repo_server_status_running() {
	if [ ! -x "$HAXE_SERVER_HELPER" ]; then
		return 1
	fi
	"$HAXE_SERVER_HELPER" status >/dev/null 2>&1
}

cleanup_repo_server() {
	if [ "$repo_server_started_here" = "1" ] && [ "$HXHX_BOOTSTRAP_KEEP_REPO_SERVER" != "1" ]; then
		if [ -x "$HAXE_SERVER_HELPER" ]; then
			"$HAXE_SERVER_HELPER" stop >/dev/null 2>&1 || true
		fi
	fi
}

trap cleanup_repo_server EXIT

run_haxe_server_preflight() {
	if [ "$HXHX_HAXE_SERVER_PREFLIGHT" != "1" ]; then
		echo "== Haxe server preflight: skipped (HXHX_HAXE_SERVER_PREFLIGHT=0)"
		return
	fi

	if [ "$HXHX_KILL_REPO_HAXE_SERVER" = "1" ]; then
		if [ ! -x "$HAXE_SERVER_HELPER" ]; then
			echo "== Haxe server preflight: cannot kill repo-owned server (missing $HAXE_SERVER_HELPER)" >&2
			exit 1
		fi
		echo "== Haxe server preflight: stopping repo-owned haxe server"
		"$HAXE_SERVER_HELPER" stop >/dev/null 2>&1 || true
	fi

	if [ "$HXHX_KILL_STALE_HAXE_SERVERS" = "1" ]; then
		kill_all_haxe_servers
		return
	fi

	local pids
	pids="$(list_haxe_server_pids)"
	if [ -z "$pids" ]; then
		echo "== Haxe server preflight: no local haxe --wait/--server-connect processes detected"
		return
	fi

	local count
	count="$(printf '%s\n' "$pids" | sed '/^$/d' | wc -l | tr -d ' ')"
	echo "== Haxe server preflight: detected $count local haxe server process(es) (informational)."
	echo "   Use --kill-repo-server for repo-owned cleanup or --kill-all-haxe-servers for global cleanup."
}

resolve_connect_arg() {
	if [ -n "$resolved_haxe_connect" ]; then
		return
	fi
	if [ "$HXHX_BOOTSTRAP_USE_REPO_SERVER" != "1" ]; then
		return
	fi
	if [ ! -x "$HAXE_SERVER_HELPER" ]; then
		echo "Missing helper script: $HAXE_SERVER_HELPER" >&2
		exit 1
	fi
	if repo_server_status_running; then
		repo_server_was_running=1
	else
		repo_server_was_running=0
	fi
	"$HAXE_SERVER_HELPER" start >/dev/null
	if [ "$repo_server_was_running" = "0" ]; then
		repo_server_started_here=1
	fi
	resolved_haxe_connect="$("$HAXE_SERVER_HELPER" port)"
}

hash_from_stdin() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | awk '{print $1}'
		return
	fi
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 | awk '{print $1}'
		return
	fi
	echo "Missing sha256 hash tool (need sha256sum or shasum)." >&2
	exit 1
}

hash_file() {
	local path="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$path" | awk '{print $1}'
		return
	fi
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$path" | awk '{print $1}'
		return
	fi
	echo "Missing sha256 hash tool (need sha256sum or shasum)." >&2
	exit 1
}

collect_fingerprint_files() {
	local file="$1"
	if [ -f "$file" ]; then
		printf '%s\n' "$file"
	fi
}

collect_fingerprint_tree() {
	local dir="$1"
	if [ ! -d "$dir" ]; then
		return
	fi
	find "$dir" -type f | LC_ALL=C sort
}

detect_stage0_haxe_mode() {
	local resolved_path="$1"
	local file_desc="$2"
	if printf '%s\n' "$file_desc" | grep -Eiq 'script|text executable'; then
		printf 'wrapper\n'
		return
	fi
	if printf '%s\n' "$resolved_path" | grep -Eiq '/node_modules/\.bin/|/\.nvm/'; then
		printf 'wrapper\n'
		return
	fi
	printf 'native\n'
}

resolve_stage0_native_haxe_candidate() {
	local resolved_path="$1"
	local detected_version="$2"

	if [ -n "$HXHX_STAGE0_NATIVE_HAXE_BIN" ] && [ -x "$HXHX_STAGE0_NATIVE_HAXE_BIN" ]; then
		printf '%s\n' "$HXHX_STAGE0_NATIVE_HAXE_BIN"
		return
	fi

	if [ -n "${HAXE_STD_PATH:-}" ]; then
		local std_parent=""
		std_parent="$(cd "${HAXE_STD_PATH}/.." 2>/dev/null && pwd || true)"
		if [ -n "$std_parent" ] && [ -x "$std_parent/haxe" ] && [ "$std_parent/haxe" != "$resolved_path" ]; then
			printf '%s\n' "$std_parent/haxe"
			return
		fi
	fi

	if [ -n "$detected_version" ] && [ -x "$HOME/haxe/versions/$detected_version/haxe" ]; then
		local home_candidate="$HOME/haxe/versions/$detected_version/haxe"
		if [ "$home_candidate" != "$resolved_path" ]; then
			printf '%s\n' "$home_candidate"
			return
		fi
	fi

	printf '\n'
}

resolve_stage0_haxe_bin() {
	stage0_haxe_resolved="$(command -v "$HAXE_BIN" 2>/dev/null || true)"
	if [ -z "$stage0_haxe_resolved" ]; then
		echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
		exit 1
	fi

	stage0_haxe_file_desc="$(file -b "$stage0_haxe_resolved" 2>/dev/null || echo unknown)"
	stage0_haxe_mode="$(detect_stage0_haxe_mode "$stage0_haxe_resolved" "$stage0_haxe_file_desc")"
	stage0_haxe_version="$("$HAXE_BIN" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
	stage0_haxe_native_candidate="$(resolve_stage0_native_haxe_candidate "$stage0_haxe_resolved" "$stage0_haxe_version")"
	stage0_haxe_switched=0

	if [ "$stage0_haxe_mode" = "wrapper" ] && [ "$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY" != "warn" ]; then
		if [ -n "$stage0_haxe_native_candidate" ] && [ "$stage0_haxe_native_candidate" != "$stage0_haxe_resolved" ]; then
			HAXE_BIN="$stage0_haxe_native_candidate"
			stage0_haxe_resolved="$stage0_haxe_native_candidate"
			stage0_haxe_file_desc="$(file -b "$stage0_haxe_resolved" 2>/dev/null || echo unknown)"
			stage0_haxe_mode="$(detect_stage0_haxe_mode "$stage0_haxe_resolved" "$stage0_haxe_file_desc")"
			stage0_haxe_version="$("$HAXE_BIN" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
			stage0_haxe_switched=1
		fi
	fi

	if [ "$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY" = "require-native" ] && [ "$stage0_haxe_mode" != "native" ]; then
		echo "Stage0 haxe policy violation: require-native, but resolved binary is wrapper: $stage0_haxe_resolved" >&2
		if [ -n "$stage0_haxe_native_candidate" ]; then
			echo "Set HAXE_BIN=$stage0_haxe_native_candidate or HXHX_STAGE0_NATIVE_HAXE_BIN=$stage0_haxe_native_candidate." >&2
		else
			echo "No native candidate auto-detected. Set HXHX_STAGE0_NATIVE_HAXE_BIN=/abs/path/to/haxe." >&2
		fi
		exit 1
	fi
}

print_stage0_haxe_selection() {
	echo "== Stage0 haxe requested: $stage0_haxe_requested"
	echo "== Stage0 haxe policy: $HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY"
	echo "== Stage0 haxe resolved: $stage0_haxe_resolved"
	echo "== Stage0 haxe mode: $stage0_haxe_mode"
	if [ -n "$stage0_haxe_version" ]; then
		echo "== Stage0 haxe version: $stage0_haxe_version"
	fi
	if [ -n "$stage0_haxe_native_candidate" ] && [ "$stage0_haxe_native_candidate" != "$stage0_haxe_resolved" ]; then
		echo "== Stage0 native candidate: $stage0_haxe_native_candidate"
	fi
	if [ "$stage0_haxe_switched" = "1" ]; then
		echo "== Stage0 haxe policy action: switched wrapper to native candidate"
	fi
	if [ "$stage0_haxe_mode" = "wrapper" ] && [ "$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY" = "warn" ]; then
		echo "== Stage0 haxe warning: wrapper mode active; set HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native to auto-upgrade when possible."
	elif [ "$stage0_haxe_mode" = "wrapper" ] && [ "$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY" = "prefer-native" ] && [ "$stage0_haxe_switched" = "0" ]; then
		echo "== Stage0 haxe warning: wrapper mode active and no native candidate was auto-detected."
	fi
}

compute_fingerprint() {
	{
		echo "schema=v1"
		echo "haxe_bin_requested=$stage0_haxe_requested"
		echo "haxe_bin_resolved=$stage0_haxe_resolved"
		echo "haxe_bin_mode=$stage0_haxe_mode"
		echo "haxe_bin_policy=$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY"
		echo "haxe_bin_switched=$stage0_haxe_switched"
		echo "haxe_native_candidate=$stage0_haxe_native_candidate"
		echo "haxe_version=$stage0_haxe_version"
		echo "stage0_disable_prepasses=$HXHX_STAGE0_DISABLE_PREPASSES"
		echo "stage0_no_opt=$HXHX_STAGE0_NO_OPT"
		echo "stage0_no_inline=$HXHX_STAGE0_NO_INLINE"
		echo "stage0_no_native_parser=$HXHX_STAGE0_NO_NATIVE_PARSER"
		echo "stage0_no_hx_parser=$HXHX_STAGE0_NO_HX_PARSER"
		echo "stage0_no_expr_macros=$HXHX_STAGE0_NO_EXPR_MACROS"
		echo "stage0_no_external_macro_host=$HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST"
		echo "stage0_no_stage3=$HXHX_STAGE0_NO_STAGE3"
		echo "stage0_no_internal_tools=$HXHX_STAGE0_NO_INTERNAL_TOOLS"
		echo "stage0_no_source_normalize_extract=$HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT"
		echo "stage0_ocaml_only=$HXHX_STAGE0_OCAML_ONLY"
		echo "stage0_no_line_directives=$HXHX_STAGE0_NO_LINE_DIRECTIVES"
		echo "stage0_ocamlrunparam=$HXHX_STAGE0_OCAMLRUNPARAM"
		echo "stage0_progress=$HXHX_STAGE0_PROGRESS"
		echo "stage0_telemetry=$HXHX_STAGE0_TELEMETRY"
		echo "stage0_telemetry_detail=$HXHX_STAGE0_TELEMETRY_DETAIL"
		echo "stage0_telemetry_class=$HXHX_STAGE0_TELEMETRY_CLASS"
		echo "stage0_telemetry_field=$HXHX_STAGE0_TELEMETRY_FIELD"
		echo "bootstrap_profile=$HXHX_BOOTSTRAP_PROFILE"

		while IFS= read -r file; do
			local rel
			rel="${file#$ROOT/}"
			echo "file=$rel:$(hash_file "$file")"
		done < <(
			collect_fingerprint_files "$ROOT/packages/hxhx/build.hxml"
			collect_fingerprint_files "$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"
			collect_fingerprint_files "$ROOT/scripts/hxhx/shard-bootstrap-ml.sh"
			collect_fingerprint_tree "$ROOT/packages/hxhx/src"
			collect_fingerprint_tree "$ROOT/packages/hxhx-core/src"
			collect_fingerprint_tree "$ROOT/packages/reflaxe.ocaml/src"
			collect_fingerprint_tree "$ROOT/packages/reflaxe.ocaml/std"
			collect_fingerprint_tree "$ROOT/haxe_libraries"
		)
	} | hash_from_stdin
}

write_fingerprint() {
	ensure_state_dir
	printf '%s\n' "$1" >"$FINGERPRINT_FILE"
}

json_escape() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	printf '%s' "$value"
}

write_report_json() {
	local report_path="$1"
	if [ -z "$report_path" ]; then
		return
	fi
	mkdir -p "$(dirname "$report_path")"
	cat >"$report_path" <<JSON
{
  "status": "$(json_escape "$script_status")",
  "exit_code": $script_exit_code,
  "mode": "$(json_escape "$([ "$HXHX_BOOTSTRAP_FAST" = "1" ] && echo fast || echo full)")",
  "skipped_emit": $skipped_emit,
  "haxe_bin": "$(json_escape "$HAXE_BIN")",
  "haxe_bin_requested": "$(json_escape "$stage0_haxe_requested")",
  "haxe_bin_resolved": "$(json_escape "$stage0_haxe_resolved")",
  "haxe_bin_mode": "$(json_escape "$stage0_haxe_mode")",
  "haxe_bin_policy": "$(json_escape "$HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY")",
  "haxe_bin_switched": $stage0_haxe_switched,
  "haxe_native_candidate": "$(json_escape "$stage0_haxe_native_candidate")",
  "haxe_version": "$(json_escape "$stage0_haxe_version")",
  "haxe_connect": "$(json_escape "$resolved_haxe_connect")",
  "stage0_disable_prepasses": $HXHX_STAGE0_DISABLE_PREPASSES,
  "stage0_no_opt": $HXHX_STAGE0_NO_OPT,
  "stage0_no_inline": $HXHX_STAGE0_NO_INLINE,
  "stage0_no_native_parser": $HXHX_STAGE0_NO_NATIVE_PARSER,
  "stage0_no_hx_parser": $HXHX_STAGE0_NO_HX_PARSER,
  "stage0_no_expr_macros": $HXHX_STAGE0_NO_EXPR_MACROS,
  "stage0_no_external_macro_host": $HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST,
  "stage0_no_stage3": $HXHX_STAGE0_NO_STAGE3,
  "stage0_no_internal_tools": $HXHX_STAGE0_NO_INTERNAL_TOOLS,
  "stage0_no_source_normalize_extract": $HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT,
  "stage0_ocaml_only": $HXHX_STAGE0_OCAML_ONLY,
  "stage0_no_line_directives": $HXHX_STAGE0_NO_LINE_DIRECTIVES,
  "dune_jobs": "$(json_escape "$HXHX_DUNE_JOBS")",
  "stage0_ocamlrunparam": "$(json_escape "$HXHX_STAGE0_OCAMLRUNPARAM")",
  "stage0_observability": {
    "heartbeat_seconds": $HXHX_STAGE0_HEARTBEAT,
    "heartbeat_samples": $stage0_heartbeat_samples,
    "heartbeat_peak_rss_mb": $stage0_heartbeat_peak_rss_mb
  },
  "phase_seconds": {
    "preflight": $phase_preflight_sec,
    "emit": $phase_emit_sec,
    "copy": $phase_copy_sec,
    "shard": $phase_shard_sec,
    "verify": $phase_verify_sec,
    "total": $total_sec
  },
  "fingerprint": "$(json_escape "$current_fingerprint")"
}
JSON
	script_report_written=1
}

on_script_exit() {
	local code="$?"
	script_exit_code="$code"
	if [ "$code" != "0" ]; then
		script_status="error"
	fi
	if [ "$code" != "0" ] \
		&& [ -n "$HXHX_BOOTSTRAP_REPORT_JSON" ] \
		&& [ "$script_report_written" != "1" ]; then
		if [ "$total_start" != "0" ] && [ "$total_sec" = "0" ]; then
			total_sec="$(( $(now_ts) - total_start ))"
		fi
		write_report_json "$HXHX_BOOTSTRAP_REPORT_JSON" || true
		echo "== Wrote regen timing report after failure (exit=$code): $HXHX_BOOTSTRAP_REPORT_JSON" >&2
	fi
	return "$code"
}

trap on_script_exit EXIT

run_stage0_emit() {
	local -a stage0_args=("$@")
	local log_file
	local metrics_file
	local emit_code
	log_file="$(create_stage0_log_file hxhx-stage0-emit)"
	metrics_file="$(create_stage0_log_file hxhx-stage0-metrics)"
	printf '0\t0\n' >"$metrics_file"
	echo "== Stage0 emit command: $HAXE_BIN ${stage0_args[*]}"
	echo "== Stage0 emit log: $log_file"

	set +e
	(
		cd "$PKG_DIR"
		local pid=""
		local heartbeat_samples_local=0
		local heartbeat_peak_rss_mb_local=0
		if [ -n "$HXHX_STAGE0_OCAMLRUNPARAM" ]; then
			OCAMLRUNPARAM="$HXHX_STAGE0_OCAMLRUNPARAM" "$HAXE_BIN" "${stage0_args[@]}" >"$log_file" 2>&1 &
		else
			"$HAXE_BIN" "${stage0_args[@]}" >"$log_file" 2>&1 &
		fi
		pid="$!"

		local interval="0"
		local status_mode="none"
		if [ -n "${HXHX_STAGE0_HEARTBEAT}" ] && [ "$HXHX_STAGE0_HEARTBEAT" != "0" ]; then
			interval="$HXHX_STAGE0_HEARTBEAT"
			status_mode="heartbeat"
		elif [ "$HXHX_STAGE0_DIAG_EVERY" != "0" ]; then
			interval="$HXHX_STAGE0_DIAG_EVERY"
			status_mode="diag"
			echo "== Stage0 emit diagnostics: heartbeat disabled; reporting every ${interval}s"
		else
			echo "== Stage0 emit diagnostics: heartbeat disabled and diag polling off."
			echo "== To inspect progress manually: tail -f \"$log_file\""
		fi

		local start_hb
		start_hb="$(now_ts)"
		local last_status_ts="$start_hb"
		while kill -0 "$pid" >/dev/null 2>&1; do
			sleep 1 || true
			local now
			now="$(now_ts)"
			if [ -n "${HXHX_STAGE0_FAILFAST_SECS}" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ]; then
				local elapsed
				elapsed="$((now - start_hb))"
				if [ "$elapsed" -ge "$HXHX_STAGE0_FAILFAST_SECS" ]; then
					echo "Stage0 emit exceeded failfast limit (${HXHX_STAGE0_FAILFAST_SECS}s). Killing pid=$pid." >&2
					kill -9 "$pid" >/dev/null 2>&1 || true
					echo "Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
					tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
					printf '%s\t%s\n' "$heartbeat_samples_local" "$heartbeat_peak_rss_mb_local" >"$metrics_file"
					exit 1
				fi
			fi
			if [ "$interval" = "0" ]; then
				continue
			fi
			if [ "$((now - last_status_ts))" -lt "$interval" ]; then
				continue
			fi
			last_status_ts="$now"

			local child_pid
			child_pid="$(pgrep -P "$pid" | head -n 1 || true)"
			local rss_probe_pid="$pid"
			if [ -n "$child_pid" ]; then
				rss_probe_pid="$child_pid"
			fi
			local rss_kb
			rss_kb="$(ps -o rss= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
			local cpu_pct
			cpu_pct="$(ps -o %cpu= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
			local proc_state
			proc_state="$(ps -o state= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
			local log_bytes
			log_bytes="$(wc -c <"$log_file" 2>/dev/null | tr -d ' ' || true)"
			local heartbeat_suffix=""
			if [ -n "$cpu_pct" ]; then
				heartbeat_suffix="$heartbeat_suffix cpu=${cpu_pct}%"
			fi
			if [ -n "$proc_state" ]; then
				heartbeat_suffix="$heartbeat_suffix state=${proc_state}"
			fi
			if [ -n "$log_bytes" ]; then
				heartbeat_suffix="$heartbeat_suffix log=${log_bytes}B"
			fi
			if [ -n "$rss_kb" ]; then
				local rss_mb
				rss_mb="$((rss_kb / 1024))"
				heartbeat_samples_local="$((heartbeat_samples_local + 1))"
				if [ "$rss_mb" -gt "$heartbeat_peak_rss_mb_local" ]; then
					heartbeat_peak_rss_mb_local="$rss_mb"
				fi
				printf '%s\t%s\n' "$heartbeat_samples_local" "$heartbeat_peak_rss_mb_local" >"$metrics_file"
				if [ -n "$child_pid" ]; then
					echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid child=$child_pid$heartbeat_suffix"
				else
					echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid$heartbeat_suffix"
				fi
			else
				if [ -n "$child_pid" ]; then
					echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s pid=$pid child=$child_pid$heartbeat_suffix"
				else
					echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s pid=$pid$heartbeat_suffix"
				fi
			fi
			if [ -n "${HXHX_STAGE0_HEARTBEAT_TAIL_LINES}" ] && [ "$HXHX_STAGE0_HEARTBEAT_TAIL_LINES" != "0" ]; then
				if [ -s "$log_file" ]; then
					echo "== Stage0 emit log tail (last $HXHX_STAGE0_HEARTBEAT_TAIL_LINES lines):"
					tail -n "$HXHX_STAGE0_HEARTBEAT_TAIL_LINES" "$log_file" || true
				else
					echo "== Stage0 emit log: (empty so far)"
				fi
			fi
		done

		set +e
		wait "$pid"
		local code="$?"
		set -e
		if [ "$code" != "0" ]; then
			echo "Stage0 emit failed (exit=$code). Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
			tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
			printf '%s\t%s\n' "$heartbeat_samples_local" "$heartbeat_peak_rss_mb_local" >"$metrics_file"
			exit "$code"
		fi
		printf '%s\t%s\n' "$heartbeat_samples_local" "$heartbeat_peak_rss_mb_local" >"$metrics_file"
	)
	emit_code="$?"
	set -e

	if [ -f "$metrics_file" ]; then
		local observed_samples=""
		local observed_peak=""
		IFS=$'\t' read -r observed_samples observed_peak <"$metrics_file" || true
		if [ -n "$observed_samples" ] && [ "$observed_samples" -gt "$stage0_heartbeat_samples" ]; then
			stage0_heartbeat_samples="$observed_samples"
		fi
		if [ -n "$observed_peak" ] && [ "$observed_peak" -gt "$stage0_heartbeat_peak_rss_mb" ]; then
			stage0_heartbeat_peak_rss_mb="$observed_peak"
		fi
	fi
	cleanup_stage0_log_file "$metrics_file"

	if [ "$emit_code" != "0" ]; then
		cleanup_stage0_log_file "$log_file"
		return "$emit_code"
	fi

	if [ "$HXHX_BOOTSTRAP_DEBUG" = "1" ]; then
		echo "== Stage0 emit completed; last $HXHX_STAGE0_LOG_TAIL_LINES lines:"
		tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" || true
	fi
	cleanup_stage0_log_file "$log_file"
}

run_bootstrap_verify() {
	if [ "$HXHX_BOOTSTRAP_VERIFY" != "1" ]; then
		echo "== Skipping bootstrap snapshot verify (HXHX_BOOTSTRAP_VERIFY=0)"
		return
	fi

	echo "== Verifying bootstrap snapshot builds (hydrate + dune)"
	rm -rf "$BOOTSTRAP_VERIFY_DIR"
	mkdir -p "$BOOTSTRAP_VERIFY_DIR"
	(cd "$BOOTSTRAP_DIR" && tar --exclude="_build" --exclude="*.install" --exclude="ocaml_profile_report.json" --exclude="ocaml_runtime_plan_report.json" -cf - .) | (cd "$BOOTSTRAP_VERIFY_DIR" && tar -xf -)
	if find "$BOOTSTRAP_VERIFY_DIR" -maxdepth 1 -type f -name "*.ml.parts" | grep -q .; then
		bash "$ROOT/scripts/hxhx/hydrate-bootstrap-shards.sh" "$BOOTSTRAP_VERIFY_DIR"
	fi
	(
		cd "$BOOTSTRAP_VERIFY_DIR"
		# NOTE: On some platforms (notably macOS/arm64), extremely large generated compilation units
		# can cause native `ocamlopt` assembly failures (e.g. "fixup value out of range").
		#
		# The bootstrap snapshot is primarily a stage0-free fallback; verifying the bytecode build
		# is sufficient to ensure the snapshot is structurally sound and runnable everywhere.
			if [ "$HXHX_DUNE_JOBS" != "auto" ]; then
				dune build -j "$HXHX_DUNE_JOBS" ./out.bc >/dev/null
			else
				dune build ./out.bc >/dev/null
			fi
	)
	rm -rf "$BOOTSTRAP_VERIFY_DIR"
}

if [ "$used_deprecated_kill_flag" = "1" ]; then
	echo "WARN: --kill-stale-haxe-servers is deprecated; prefer --kill-all-haxe-servers." >&2
fi

resolve_stage0_haxe_bin

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
	echo "Missing dune/ocamlc on PATH." >&2
	exit 1
fi

if [ ! -d "$PKG_DIR" ]; then
	echo "Missing package directory: $PKG_DIR" >&2
	exit 1
fi

echo "== Regenerating hxhx via stage0 (this requires Haxe + reflaxe.ocaml)"
print_stage0_haxe_selection
if [ "$HXHX_DUNE_JOBS" != "auto" ]; then
	export DUNE_JOBS="$HXHX_DUNE_JOBS"
	echo "== Dune jobs: forced to $HXHX_DUNE_JOBS (HXHX_DUNE_JOBS)"
elif [ -n "${DUNE_JOBS:-}" ]; then
	echo "== Dune jobs: inherited DUNE_JOBS=$DUNE_JOBS (HXHX_DUNE_JOBS=auto)"
else
	echo "== Dune jobs: auto (HXHX_DUNE_JOBS=auto)"
fi
if [ "$HXHX_BOOTSTRAP_FAST" = "1" ]; then
	echo "== Mode: fast (clean_out=${HXHX_BOOTSTRAP_CLEAN_OUT}, verify=${HXHX_BOOTSTRAP_VERIFY})"
else
	echo "== Mode: full (clean_out=${HXHX_BOOTSTRAP_CLEAN_OUT}, verify=${HXHX_BOOTSTRAP_VERIFY})"
fi
if [ "$HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED" = "1" ]; then
	echo "== Fingerprint skip: enabled"
fi
if [ -z "${HXHX_STAGE0_HEARTBEAT}" ] || [ "$HXHX_STAGE0_HEARTBEAT" = "0" ]; then
	echo "== Stage0 heartbeat: disabled (set HXHX_STAGE0_HEARTBEAT=<seconds> to enable)"
else
	echo "== Stage0 heartbeat: every ${HXHX_STAGE0_HEARTBEAT}s (set HXHX_STAGE0_HEARTBEAT=0 to disable)"
fi
if [ -n "${HXHX_STAGE0_FAILFAST_SECS}" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ]; then
	echo "== Stage0 failfast: ${HXHX_STAGE0_FAILFAST_SECS}s"
else
	echo "== Stage0 failfast: disabled"
fi
if [ "$HXHX_BOOTSTRAP_PROFILE" = "1" ]; then
	echo "== Stage0 profile mode: enabled (--times + -D filter-times)"
fi
if [ "$HXHX_STAGE0_NO_OPT" = "1" ]; then
	echo "== Stage0 compile mode: --no-opt enabled"
fi
if [ "$HXHX_STAGE0_NO_INLINE" = "1" ]; then
	echo "== Stage0 compile mode: --no-inline enabled"
fi
if [ "$HXHX_STAGE0_NO_NATIVE_PARSER" = "1" ]; then
	echo "== Stage0 compile mode: native parser disabled (-D hxhx_stage0_no_native_parser)"
fi
if [ "$HXHX_STAGE0_NO_HX_PARSER" = "1" ]; then
	echo "== Stage0 compile mode: pure-Haxe parser fallbacks trimmed (-D hxhx_stage0_no_hx_parser)"
fi
if [ "$HXHX_STAGE0_NO_EXPR_MACROS" = "1" ]; then
	echo "== Stage0 compile mode: Stage3 expression macros disabled (-D hxhx_stage0_no_expr_macros)"
fi
if [ "$HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST" = "1" ]; then
	echo "== Stage0 compile mode: external macro-host runtime paths disabled (-D hxhx_stage0_no_external_macro_host)"
fi
if [ "$HXHX_STAGE0_NO_STAGE3" = "1" ]; then
	echo "== Stage0 compile mode: Stage3 native lane paths disabled (-D hxhx_stage0_no_stage3)"
fi
if [ "$HXHX_STAGE0_NO_INTERNAL_TOOLS" = "1" ]; then
	echo "== Stage0 compile mode: internal bring-up CLI paths disabled (-D hxhx_stage0_no_internal_tools)"
fi
if [ "$HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT" = "1" ]; then
	echo "== Stage0 compile mode: HxParser normalization helpers inlined (-D hxhx_stage0_no_source_normalize_extract)"
fi
if [ "$HXHX_STAGE0_OCAML_ONLY" = "1" ]; then
	echo "== Stage0 compile mode: ocaml-only backend graph enabled (-D hxhx_stage0_ocaml_only)"
fi
if [ "$HXHX_STAGE0_NO_LINE_DIRECTIVES" = "1" ]; then
	echo "== Stage0 compile mode: line directives disabled (-D ocaml_no_line_directives)"
fi
if [ -n "$HXHX_STAGE0_OCAMLRUNPARAM" ]; then
	echo "== Stage0 OCaml runtime tuning: OCAMLRUNPARAM=$HXHX_STAGE0_OCAMLRUNPARAM"
fi
if [ "$HXHX_KEEP_LOGS" = "1" ]; then
	echo "== Stage0 logs: retained (HXHX_KEEP_LOGS=1)"
fi
if [ -n "$HXHX_LOG_DIR" ]; then
	echo "== Stage0 logs directory: $HXHX_LOG_DIR"
fi
if [ "$HXHX_STAGE0_DIAG_EVERY" != "0" ]; then
	echo "== Stage0 disabled-heartbeat diagnostics: every ${HXHX_STAGE0_DIAG_EVERY}s"
fi

if [ "$HXHX_STAGE0_SELECTION_ONLY" = "1" ]; then
	echo "== Stage0 selection-only mode: skipping preflight/emit/copy/shard/verify"
	skipped_emit=1
	total_sec=0
	write_report_json "$HXHX_BOOTSTRAP_REPORT_JSON"
	if [ -n "$HXHX_BOOTSTRAP_REPORT_JSON" ]; then
		echo "== Wrote regen timing report: $HXHX_BOOTSTRAP_REPORT_JSON"
	fi
	echo "OK: stage0 haxe selection resolved"
	exit 0
fi

total_start="$(now_ts)"

preflight_start="$(now_ts)"
run_haxe_server_preflight
phase_preflight_sec="$(( $(now_ts) - preflight_start ))"

resolve_connect_arg
if [ -n "$resolved_haxe_connect" ]; then
	echo "== Stage0 connect endpoint: $resolved_haxe_connect"
fi

current_fingerprint="$(compute_fingerprint)"
if [ "$HXHX_BOOTSTRAP_SKIP_IF_UNCHANGED" = "1" ] \
	&& [ "$HXHX_BOOTSTRAP_FORCE" != "1" ] \
	&& [ -f "$FINGERPRINT_FILE" ] \
	&& [ -d "$BOOTSTRAP_DIR" ] \
	&& [ "$current_fingerprint" = "$(cat "$FINGERPRINT_FILE")" ]; then
	skipped_emit=1
	echo "== Stage0 emit skipped (fingerprint unchanged)"
else
	skipped_emit=0
fi

if [ "$skipped_emit" = "0" ]; then
	emit_start="$(now_ts)"
	if [ "$HXHX_BOOTSTRAP_CLEAN_OUT" = "1" ]; then
		rm -rf "$OUT_DIR"
	fi
	mkdir -p "$OUT_DIR"
	haxe_args=(build.hxml -D ocaml_emit_only)
	if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
		haxe_args+=(-v)
	fi
	if [ -n "$resolved_haxe_connect" ]; then
		haxe_args+=(--connect "$resolved_haxe_connect")
	fi
	if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
		haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
	fi
	if [ "$HXHX_STAGE0_TELEMETRY_DETAIL" = "1" ]; then
		haxe_args+=(-D reflaxe_ocaml_telemetry_detail)
	fi
	if [ -n "$HXHX_STAGE0_TELEMETRY_CLASS" ]; then
		haxe_args+=(-D "reflaxe_ocaml_telemetry_class=$HXHX_STAGE0_TELEMETRY_CLASS")
	fi
	if [ -n "$HXHX_STAGE0_TELEMETRY_FIELD" ]; then
		haxe_args+=(-D "reflaxe_ocaml_telemetry_field=$HXHX_STAGE0_TELEMETRY_FIELD")
	fi
	if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
		haxe_args+=(-D reflaxe_ocaml_progress)
	fi
	if [ "$HXHX_STAGE0_TELEMETRY" = "1" ]; then
		haxe_args+=(-D reflaxe_ocaml_telemetry)
	fi
	if [ "$HXHX_STAGE0_NO_OPT" = "1" ]; then
		haxe_args+=(--no-opt)
	fi
	if [ "$HXHX_STAGE0_NO_INLINE" = "1" ]; then
		haxe_args+=(--no-inline)
	fi
	if [ "$HXHX_STAGE0_NO_NATIVE_PARSER" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_native_parser)
	fi
	if [ "$HXHX_STAGE0_NO_HX_PARSER" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_hx_parser)
	fi
	if [ "$HXHX_STAGE0_NO_EXPR_MACROS" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_expr_macros)
	fi
	if [ "$HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_external_macro_host)
	fi
	if [ "$HXHX_STAGE0_NO_STAGE3" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_stage3)
	fi
	if [ "$HXHX_STAGE0_NO_INTERNAL_TOOLS" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_internal_tools)
	fi
	if [ "$HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_no_source_normalize_extract)
	fi
	if [ "$HXHX_STAGE0_OCAML_ONLY" = "1" ]; then
		haxe_args+=(-D hxhx_stage0_ocaml_only)
	fi
	if [ "$HXHX_STAGE0_NO_LINE_DIRECTIVES" = "1" ]; then
		haxe_args+=(-D ocaml_no_line_directives)
	fi
	if [ "$HXHX_BOOTSTRAP_PROFILE" = "1" ]; then
		haxe_args+=(-D filter-times --times)
	elif [ "$HXHX_BOOTSTRAP_DEBUG" = "1" ]; then
		haxe_args+=(--times)
	fi

	run_stage0_emit "${haxe_args[@]}"
	phase_emit_sec="$(( $(now_ts) - emit_start ))"
	echo "== Stage0 emit duration: ${phase_emit_sec}s"

	if [ ! -d "$OUT_DIR" ]; then
		echo "Missing generated output directory: $OUT_DIR" >&2
		exit 1
	fi

	copy_start="$(now_ts)"
	echo "== Updating bootstrap snapshot: $BOOTSTRAP_DIR"
	rm -rf "$BOOTSTRAP_DIR"
	mkdir -p "$BOOTSTRAP_DIR"
	# Copy everything except build artifacts and generator sources.
	(cd "$OUT_DIR" && tar --exclude='_build' --exclude='_gen_hx' --exclude='ocaml_profile_report.json' --exclude='ocaml_runtime_plan_report.json' -cf - .) | (cd "$BOOTSTRAP_DIR" && tar -xf -)
	phase_copy_sec="$(( $(now_ts) - copy_start ))"

	shard_start="$(now_ts)"
	echo "== Sharding oversized bootstrap OCaml units (max ${HXHX_BOOTSTRAP_SHARD_MAX_BYTES:-50000000}B)"
	bash "$ROOT/scripts/hxhx/shard-bootstrap-ml.sh" "$BOOTSTRAP_DIR"
	phase_shard_sec="$(( $(now_ts) - shard_start ))"

	bootstrap_files="$(find "$BOOTSTRAP_DIR" -type f | wc -l | tr -d ' ')"
	echo "== Bootstrap snapshot copy duration: ${phase_copy_sec}s (files=$bootstrap_files)"
	echo "== Bootstrap snapshot sharding duration: ${phase_shard_sec}s"

	write_fingerprint "$current_fingerprint"
fi

verify_start="$(now_ts)"
run_bootstrap_verify
phase_verify_sec="$(( $(now_ts) - verify_start ))"
if [ "$HXHX_BOOTSTRAP_VERIFY" = "1" ]; then
	echo "== Bootstrap verification duration: ${phase_verify_sec}s"
fi

total_sec="$(( $(now_ts) - total_start ))"
echo "== Total regenerate duration: ${total_sec}s"

write_report_json "$HXHX_BOOTSTRAP_REPORT_JSON"
if [ -n "$HXHX_BOOTSTRAP_REPORT_JSON" ]; then
	echo "== Wrote regen timing report: $HXHX_BOOTSTRAP_REPORT_JSON"
fi

if [ "$skipped_emit" = "1" ]; then
	echo "OK: bootstrap snapshot unchanged"
else
	echo "OK: regenerated bootstrap snapshot"
fi
