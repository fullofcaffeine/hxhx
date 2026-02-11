#!/usr/bin/env bash
set -euo pipefail

# Display smoke rung (Stage3 no-emit, non-delegating).
#
# Goal
# - Exercise `--display <file@mode>` argument handling through `hxhx --hxhx-stage3 --hxhx-no-emit`
#   without relying on the upstream `--wait` display server protocol.
#
# Why this exists
# - Gate2's direct runner currently compiles `tests/display/build.hxml` but does not execute the
#   display server fixture process end-to-end under Stage3 no-emit.
# - This script provides a reproducible, dedicated display compatibility check while we continue
#   implementing full server parity.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/display" ]; then
  echo "Skipping upstream display smoke (stage3 no-emit): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream display smoke (stage3 no-emit): dune/ocamlc not found on PATH."
  exit 0
fi

if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

DISPLAY_FILE="$UPSTREAM_DIR/tests/display/src-shared/Marker.hx"
if [ ! -f "$DISPLAY_FILE" ]; then
  echo "Missing upstream display fixture file: $DISPLAY_FILE" >&2
  exit 1
fi

echo "== Upstream display smoke (stage3 no-emit): $DISPLAY_FILE"
out="$(
  "$HXHX_BIN" \
    --hxhx-stage3 --hxhx-no-emit \
    --hxhx-out "$UPSTREAM_DIR/tests/display/out_hxhx_display_stage3_no_emit" \
    --connect 6000 \
    --display "$DISPLAY_FILE@0@diagnostics" \
    -cp "$UPSTREAM_DIR/tests/display/src" \
    -cp "$UPSTREAM_DIR/tests/display/src-shared" \
    --no-output 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage3=no_emit_ok$"
echo "$out" | grep -qv "import_missing 6000"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Skipping wait-stdio display smoke: python3 not found on PATH."
  exit 0
fi

echo "== Upstream display wait-stdio smoke (stage3 no-emit)"
HXHX_BIN_FOR_PY="$HXHX_BIN" UPSTREAM_DIR_FOR_PY="$UPSTREAM_DIR" python3 - <<'PY'
import os
import struct
import subprocess
import sys

hxhx_bin = os.environ["HXHX_BIN_FOR_PY"]
upstream = os.environ["UPSTREAM_DIR_FOR_PY"]
display_file = os.path.join(upstream, "tests", "display", "src-shared", "Marker.hx")
cp_src = os.path.join(upstream, "tests", "display", "src")
cp_shared = os.path.join(upstream, "tests", "display", "src-shared")
out_dir = os.path.join(upstream, "tests", "display", "out_hxhx_display_wait_stdio")

args = [
    "--display", display_file + "@0@diagnostics",
    "-cp", cp_src,
    "-cp", cp_shared,
    "--no-output",
]
payload = ("\n".join(args) + "\n").encode("utf-8")
frame = struct.pack("<i", len(payload)) + payload

proc = subprocess.Popen(
    [hxhx_bin, "--hxhx-stage3", "--hxhx-no-emit", "--hxhx-out", out_dir, "--wait", "stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

try:
    assert proc.stdin is not None
    assert proc.stderr is not None
    proc.stdin.write(frame)
    proc.stdin.flush()

    header = proc.stderr.read(4)
    if len(header) != 4:
        raise RuntimeError("missing wait-stdio response header")
    size = struct.unpack("<i", header)[0]
    body = proc.stderr.read(size)
    if len(body) != size:
        raise RuntimeError("truncated wait-stdio response")

    is_error = len(body) > 0 and body[0] == 0x02
    text = body[1:].decode("utf-8", errors="replace") if is_error else body.decode("utf-8", errors="replace")
    if is_error:
        raise RuntimeError("wait-stdio response flagged error: " + text)
    if '[{"diagnostics":[]}]' not in text:
        raise RuntimeError("unexpected diagnostics payload: " + text)
finally:
    if proc.stdin is not None:
        proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
        raise RuntimeError("wait-stdio server did not exit after stdin close")
    if proc.returncode != 0:
        raise RuntimeError(f"wait-stdio server exited with code {proc.returncode}")

print("wait_stdio=ok")
PY
