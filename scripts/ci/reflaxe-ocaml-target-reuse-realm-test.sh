#!/usr/bin/env bash
set -euo pipefail

# Proves the physical lifetime of Reflaxe's bounded in-memory catalog owner.
# Every request still runs the ordinary OCaml target and remains reuse-ineligible.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/reflaxe_ocaml_target_reuse_realm"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
VALIDATOR="$ROOT/scripts/ci/reflaxe-ocaml-target-reuse-realm-helper.js"
HAXE_BIN="${HAXE_BIN:-haxe}"
WORK_DIR="$(mktemp -d "$ROOT/.reflaxe-ocaml-target-reuse-realm.XXXXXX")"
PROJECT_DIR="$WORK_DIR/project"
SNAPSHOT_DIR="$WORK_DIR/snapshots"
SERVER_STATE_DIR="$WORK_DIR/server-state"
SERVER_PORT="${REFLAXE_OCAML_REALM_TEST_PORT:-$((26000 + ($$ % 10000)))}"
SERVER_STARTED=0

cleanup() {
	if [[ "$SERVER_STARTED" = "1" ]]; then
		HXHX_STATE_DIR="$SERVER_STATE_DIR" \
			HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
			HAXE_BIN="$HAXE_BIN" \
			bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
	fi
	if [[ "${REFLAXE_OCAML_REALM_KEEP:-0}" = "1" ]]; then
		echo "reflaxe.ocaml target reuse realm test: retained $WORK_DIR" >&2
	elif [[ -d "$WORK_DIR" ]]; then
		find "$WORK_DIR" -depth -delete
	fi
}
trap cleanup EXIT

fail() {
	echo "reflaxe.ocaml target reuse realm test: $*" >&2
	exit 1
}

start_server() {
	if "$HAXE_BIN" --connect "$SERVER_PORT" --version >/dev/null 2>&1; then
		fail "chosen compiler-server port $SERVER_PORT is already in use"
	fi
	HXHX_STATE_DIR="$SERVER_STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$SERVER_HELPER" start >/dev/null
	SERVER_STARTED=1
}

stop_server() {
	HXHX_STATE_DIR="$SERVER_STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$SERVER_HELPER" stop >/dev/null
	SERVER_STARTED=0
}

compile_server() {
	(
		cd "$PROJECT_DIR"
		"$HAXE_BIN" --connect "$SERVER_PORT" "$@" build.hxml
	)
}

snapshot_report() {
	local label="$1"
	local report="$PROJECT_DIR/out/ocaml_target_reuse_observation.json"
	[[ -f "$report" ]] || fail "request '$label' did not publish the observation report"
	cp "$report" "$SNAPSHOT_DIR/$label.json"
	echo "REFLAXE_OCAML_TARGET_REUSE_REALM_STATE:PASS state=$label"
}

mkdir -p "$PROJECT_DIR" "$SNAPSHOT_DIR" "$PROJECT_DIR/alternate"
cp "$FIXTURE/build.hxml" "$PROJECT_DIR/build.hxml"
cp -R "$FIXTURE/src" "$PROJECT_DIR/src"
cp "$FIXTURE/variants/RealmBuildMacro.one.hx" "$PROJECT_DIR/src/RealmBuildMacro.hx"

if [[ "$("$HAXE_BIN" --version)" != "4.3.7" ]]; then
	fail "expected upstream Haxe 4.3.7"
fi

start_server
compile_server
snapshot_report cold

compile_server
snapshot_report repeat

compile_server --macro 'TargetReuseRealmControl.reset("fixture-explicit-reset")'
snapshot_report explicit-reset

cp "$FIXTURE/variants/RealmBuildMacro.two.hx" "$PROJECT_DIR/src/RealmBuildMacro.hx"
compile_server
snapshot_report macro-change

if compile_server --macro 'RealmBuildMacro.failRequest()' >"$WORK_DIR/expected-macro-error.log" 2>&1; then
	fail "injected macro error unexpectedly succeeded"
fi
grep -Fq "injected target-reuse macro failure" "$WORK_DIR/expected-macro-error.log" \
	|| fail "injected macro error did not preserve its diagnostic"
compile_server
snapshot_report after-macro-error

compile_server -D no-macro-cache
snapshot_report no-macro-cache
compile_server
snapshot_report after-no-macro-cache

compile_server -cp "$PROJECT_DIR/alternate"
snapshot_report signature-change
compile_server
snapshot_report signature-restored

stop_server
start_server
compile_server
snapshot_report restart
stop_server

node "$VALIDATOR" "$SNAPSHOT_DIR"
