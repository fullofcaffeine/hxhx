#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
FIXTURE="$ROOT/test/reflaxe_ocaml_throw_runtime_use"
OUTPUT="$ROOT/.tmp/reflaxe-ocaml-throw-output-copy"

case "$OUTPUT" in
  "$ROOT"/.tmp/*) ;;
  *)
    echo "Refusing to clean an output path outside the repository temporary directory." >&2
    exit 1
    ;;
esac

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

"$HAXE_BIN" -cp "$FIXTURE/src" --run ThrowOutputCopyMain > "$OUTPUT/upstream.stdout"
diff -u "$FIXTURE/expected-output-copy.stdout" "$OUTPUT/upstream.stdout"

(
  cd "$ROOT"
  "$HAXE_BIN" "$FIXTURE/output-copy.hxml" -D ocaml_build=native
)

GENERATED="$OUTPUT/out/ThrowOutputCopyMain.ml"
EXE="$OUTPUT/out/_build/default/out.exe"
if [[ ! -f "$GENERATED" || ! -x "$EXE" ]]; then
  echo "The throw output-copy fixture did not produce its generated module and executable." >&2
  exit 1
fi

throw_literal_count="$({ grep -o '"unexpected"' "$GENERATED" || true; } | wc -l | tr -d ' ')"
if [[ "$throw_literal_count" != "2" ]]; then
  echo "Expected one source throw to occupy two final nullable-switch sites; found $throw_literal_count." >&2
  exit 1
fi

"$EXE" > "$OUTPUT/ocaml.stdout"
diff -u "$FIXTURE/expected-output-copy.stdout" "$OUTPUT/ocaml.stdout"

echo "REFLAXE_OCAML_THROW_OUTPUT_COPY:PASS"
