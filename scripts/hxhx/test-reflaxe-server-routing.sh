#!/usr/bin/env bash
set -euo pipefail

# Proves that the stage0 hxhx build accepts the supported upstream-Haxe server
# route without a hidden override. Semantic clean/warm equivalence is covered
# by reflaxe-ocaml-complete-program-server-test.sh; this fixture owns only the
# build-script handoff and its generated-output boundary.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d)"
FAKE_HAXE="$TEST_TMP/fake-haxe.sh"
TRACE_FILE="$TEST_TMP/fake-haxe.trace"
BUILD_OUTPUT_DIR="$TEST_TMP/stage0-out"
BUILD_OUTPUT="$TEST_TMP/build.output"
ENDPOINT="127.0.0.1:17107"

cleanup() {
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

fail() {
	echo "[test-reflaxe-server-routing] ERROR: $*" >&2
	exit 1
}

cat >"$FAKE_HAXE" <<'FAKE_HAXE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_HAXE_TRACE:?}"

has_connect=0
endpoint=""
expect_endpoint=0
for arg in "$@"; do
	if [ "$expect_endpoint" = "1" ]; then
		endpoint="$arg"
		expect_endpoint=0
	elif [ "$arg" = "--connect" ]; then
		has_connect=1
		expect_endpoint=1
	elif [ "$arg" = "--version" ] || [ "$arg" = "-version" ]; then
		echo "4.3.7"
		exit 0
	fi
done

[ "$has_connect" = "1" ] || {
	echo "expected stage0 compile to use --connect" >&2
	exit 97
}
[ "$endpoint" = "${FAKE_EXPECTED_ENDPOINT:?}" ] || {
	echo "unexpected server endpoint: $endpoint" >&2
	exit 98
}

mkdir -p "${FAKE_STAGE0_OUTPUT:?}"
cat >"$FAKE_STAGE0_OUTPUT/dune-project" <<'DUNE_PROJECT'
(lang dune 3.0)
DUNE_PROJECT
cat >"$FAKE_STAGE0_OUTPUT/dune" <<DUNE
(rule
 (target ${FAKE_STAGE0_EXECUTABLE:?}.bc)
 (action (write-file %{target} "")))
DUNE
FAKE_HAXE
chmod +x "$FAKE_HAXE"

(
	cd "$ROOT"
	FAKE_HAXE_TRACE="$TRACE_FILE" \
	FAKE_EXPECTED_ENDPOINT="$ENDPOINT" \
	FAKE_STAGE0_OUTPUT="$BUILD_OUTPUT_DIR" \
	FAKE_STAGE0_EXECUTABLE="stage0_out" \
	HXHX_FORCE_STAGE0=1 \
	HXHX_STAGE0_OUTPUT_DIR="$BUILD_OUTPUT_DIR" \
	HXHX_BOOTSTRAP_HEARTBEAT=0 \
	HAXE_CONNECT="$ENDPOINT" \
	HAXE_BIN="$FAKE_HAXE" \
		bash scripts/hxhx/build-hxhx.sh
) >"$BUILD_OUTPUT" 2>&1

grep -F -- "--connect $ENDPOINT" "$TRACE_FILE" >/dev/null \
	|| fail "stage0 build did not forward the selected server endpoint"
[ -f "$BUILD_OUTPUT_DIR/_build/default/stage0_out.bc" ] \
	|| fail "stage0 build did not complete through the server route"
retired_override="HXHX_ALLOW_INCOMPLETE_REFLAXE_""SERVER_REUSE"
if rg -n "$retired_override" \
	scripts/hxhx scripts/ci package.json .github/workflows docs packages/hxhx/README.md >/dev/null 2>&1; then
	fail "retired incomplete-server override is still referenced"
fi

echo "REFLAXE_SERVER_ROUTING:PASS"
