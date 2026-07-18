#!/usr/bin/env bash
set -euo pipefail

# Prove that a source build can target an isolated directory and refuses to use
# tracked source as disposable output. The fast profile relies on this boundary.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d)"
FAKE_HAXE="$TEST_TMP/fake-haxe.sh"
TRACE_FILE="$TEST_TMP/fake-haxe.trace"
CUSTOM_OUT="$TEST_TMP/current-source-fast"
OUTPUT_FILE="$TEST_TMP/build.output"
mkdir -p "$CUSTOM_OUT"
CUSTOM_OUT="$(cd "$CUSTOM_OUT" && pwd -P)"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

cat >"$FAKE_HAXE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${FAKE_HAXE_TRACE:?missing FAKE_HAXE_TRACE}"
output_dir=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-D" ] && [ "$#" -ge 2 ]; then
    case "$2" in
      ocaml_output=*) output_dir="${2#ocaml_output=}" ;;
    esac
    shift 2
    continue
  fi
  shift
done
[ -n "$output_dir" ] || {
  echo "fake haxe did not receive an ocaml_output override" >&2
  exit 2
}
mkdir -p "$output_dir"
exe_name="$(basename "$output_dir" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]/_/g')"
case "$exe_name" in
  [0-9]*) exe_name="_$exe_name" ;;
esac
cat >"$output_dir/dune-project" <<'DUNE'
(lang dune 3.0)
DUNE
cat >"$output_dir/dune" <<DUNE
(executable
 (name $exe_name)
 (modes (byte exe)))
DUNE
printf 'let () = ()\n' >"$output_dir/$exe_name.ml"
EOF
chmod +x "$FAKE_HAXE"

HXHX_FORCE_STAGE0=1 \
HAXE_BIN="$FAKE_HAXE" \
FAKE_HAXE_TRACE="$TRACE_FILE" \
HXHX_STAGE0_OUTPUT_DIR="$CUSTOM_OUT" \
HXHX_STAGE0_HEARTBEAT=0 \
HXHX_STAGE0_FAILFAST_SECS=0 \
HXHX_BOOTSTRAP_HEARTBEAT=0 \
bash "$ROOT/scripts/hxhx/build-hxhx.sh" >"$OUTPUT_FILE" 2>&1

grep -Fq -- "-D ocaml_output=$CUSTOM_OUT" "$TRACE_FILE" || {
  echo "custom output build did not forward its Reflaxe output directory" >&2
  cat "$TRACE_FILE" >&2
  exit 1
}
expected="$CUSTOM_OUT/_build/default/current_source_fast.bc"
[ "$(tail -n 1 "$OUTPUT_FILE")" = "$expected" ] || {
  echo "custom output build returned the wrong artifact path" >&2
  cat "$OUTPUT_FILE" >&2
  exit 1
}
[ -f "$expected" ]

set +e
HXHX_FORCE_STAGE0=1 \
HAXE_BIN="$FAKE_HAXE" \
FAKE_HAXE_TRACE="$TRACE_FILE" \
HXHX_STAGE0_OUTPUT_DIR="$ROOT/packages/hxhx/src" \
bash "$ROOT/scripts/hxhx/build-hxhx.sh" >"$TEST_TMP/unsafe.output" 2>&1
unsafe_code="$?"
set -e
[ "$unsafe_code" -eq 2 ] || {
  echo "tracked source was not rejected as a Stage0 output directory" >&2
  cat "$TEST_TMP/unsafe.output" >&2
  exit 1
}
grep -Fq 'Unsafe HXHX_STAGE0_OUTPUT_DIR contains tracked files' "$TEST_TMP/unsafe.output"

echo "BUILD_HXHX_OUTPUT_DIR_SMOKE:PASS"
