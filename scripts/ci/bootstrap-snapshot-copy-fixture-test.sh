#!/usr/bin/env bash
# Prove that bootstrap snapshot copying keeps generated source while dropping
# temporary build-only files.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COPY_SCRIPT="$ROOT/scripts/hxhx/copy-bootstrap-snapshot.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-bootstrap-snapshot-copy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

generated="$fixture/generated"
snapshot="$fixture/snapshot"
mkdir -p "$generated/_build" "$generated/_gen_hx" "$generated/runtime" "$snapshot"

printf '%s\n' 'let main = ()' >"$generated/Main.ml"
printf '%s\n' '(executable (name out))' >"$generated/dune"
printf '%s\n' 'let runtime = ()' >"$generated/runtime/Runtime.ml"
printf '%s\n' '{"files":[]}' >"$generated/_GeneratedFiles.json"
printf '%s\n' 'temporary object' >"$generated/_build/out.o"
printf '%s\n' 'temporary generator source' >"$generated/_gen_hx/Main.hx"
printf '%s\n' '{"profile":true}' >"$generated/ocaml_profile_report.json"
printf '%s\n' '{"runtime":true}' >"$generated/ocaml_runtime_plan_report.json"
printf '%s\n' 'HXHX_BIN=/temporary/current-source/out.bc' >"$generated/hxhx-current-source.env"

bash "$COPY_SCRIPT" "$generated" "$snapshot"

for required in Main.ml dune runtime/Runtime.ml _GeneratedFiles.json; do
	if [ ! -f "$snapshot/$required" ]; then
		echo "[bootstrap-snapshot-copy-fixture-test] missing generated snapshot file: $required" >&2
		exit 1
	fi
done

for excluded in _build/out.o _gen_hx/Main.hx ocaml_profile_report.json ocaml_runtime_plan_report.json hxhx-current-source.env; do
	if [ -e "$snapshot/$excluded" ]; then
		echo "[bootstrap-snapshot-copy-fixture-test] copied temporary build file: $excluded" >&2
		exit 1
	fi
done

echo "BOOTSTRAP_SNAPSHOT_COPY_FIXTURE:PASS"
