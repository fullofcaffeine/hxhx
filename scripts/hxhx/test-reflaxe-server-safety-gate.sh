#!/usr/bin/env bash
set -euo pipefail

# Warm Haxe-server requests currently give Reflaxe only a partial rebuild view,
# while reflaxe.ocaml also needs complete whole-program target state. These
# checks prove the public hxhx development workflows stop before target output
# is deleted or generated unless a maintainer deliberately enables the
# diagnostic-only lifecycle path.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d)"
FAKE_HAXE="$TEST_TMP/fake-haxe.sh"
TRACE_FILE="$TEST_TMP/fake-haxe.trace"
BUILD_OUTPUT_DIR="$TEST_TMP/stage0-out"

cleanup() {
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

fail() {
	echo "[test-reflaxe-server-safety-gate] ERROR: $*" >&2
	exit 1
}

cat >"$FAKE_HAXE" <<'FAKE_HAXE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_HAXE_TRACE:?}"
case " ${*} " in
	*" --version "*|*" -version "*)
		echo "4.3.7"
		exit 0
		;;
esac
exit 97
FAKE_HAXE
chmod +x "$FAKE_HAXE"

mkdir -p "$BUILD_OUTPUT_DIR"
printf 'keep\n' >"$BUILD_OUTPUT_DIR/sentinel"

run_blocked_build() {
	local label="$1"
	shift
	local output="$TEST_TMP/build-$label.output"
	set +e
	(
		cd "$ROOT"
		FAKE_HAXE_TRACE="$TRACE_FILE" \
		HXHX_FORCE_STAGE0=1 \
		HXHX_STAGE0_OUTPUT_DIR="$BUILD_OUTPUT_DIR" \
		HAXE_BIN="$FAKE_HAXE" \
			"$@" bash scripts/hxhx/build-hxhx.sh
	) >"$output" 2>&1
	local code="$?"
	set -e
	[ "$code" = "2" ] || fail "$label build returned $code instead of safety exit 2"
	grep -F "temporarily disabled for correctness" "$output" >/dev/null \
		|| fail "$label build omitted the actionable safety diagnostic"
	[ -f "$BUILD_OUTPUT_DIR/sentinel" ] || fail "$label build deleted target output before rejecting server reuse"
}

run_blocked_build helper env HXHX_STAGE0_USE_REPO_SERVER=1
run_blocked_build explicit env HAXE_CONNECT=127.0.0.1:17107

if [ -s "$TRACE_FILE" ]; then
	fail "blocked build invoked Haxe before rejecting server reuse"
fi

regen_output="$TEST_TMP/regen.output"
set +e
(
	cd "$ROOT"
	FAKE_HAXE_TRACE="$TRACE_FILE" \
	HAXE_BIN="$FAKE_HAXE" \
	HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=warn \
	HXHX_HAXE_SERVER_PREFLIGHT=0 \
		bash scripts/hxhx/regenerate-hxhx-bootstrap.sh \
		--incremental --use-repo-server --no-verify --force
) >"$regen_output" 2>&1
regen_code="$?"
set -e

[ "$regen_code" = "2" ] || fail "bootstrap regeneration returned $regen_code instead of safety exit 2"
grep -F "temporarily disabled for correctness" "$regen_output" >/dev/null \
	|| fail "bootstrap regeneration omitted the actionable safety diagnostic"
if grep -E '(^| )build\.hxml( |$)|(^| )--wait( |$)' "$TRACE_FILE" >/dev/null 2>&1; then
	fail "blocked bootstrap regeneration started a server or target compile"
fi

echo "REFLAXE_SERVER_SAFETY_GATE:PASS"
