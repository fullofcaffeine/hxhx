#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_DIR="$ROOT/tools/hxhx-macro-host"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx macro host build: dune/ocamlc not found on PATH."
  exit 0
fi

if [ ! -d "$TOOL_DIR" ]; then
  echo "Missing tool directory: $TOOL_DIR" >&2
  exit 1
fi

normalize_cp() {
  local cp="$1"
  if [ -z "$cp" ]; then
    return 0
  fi
  # Treat relative classpaths as repo-root relative, because this script `cd`s
  # into `tools/hxhx-macro-host` before invoking the Haxe compiler.
  if [[ "$cp" != /* ]]; then
    cp="$ROOT/$cp"
  fi
  echo "$cp"
}

escape_hx_string() {
  local s="$1"
  # Escape for inclusion inside a Haxe string literal.
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  echo "$s"
}

trim_ws() {
  # Trim leading/trailing whitespace without interpreting quotes.
  echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

(
  cd "$TOOL_DIR"
  rm -rf out
  mkdir -p out
  extra=()
  gen_cp=""
  if [ -n "${HXHX_MACRO_HOST_ENTRYPOINTS:-}" ]; then
    gen_cp="$TOOL_DIR/out/_gen_hx"
    mkdir -p "$gen_cp/hxhxmacrohost"
    gen_file="$gen_cp/hxhxmacrohost/EntryPointsGen.hx"

    # Generate a tiny registry that avoids reflection.
    #
    # `HXHX_MACRO_HOST_ENTRYPOINTS` is a `;`-separated list of exact expression strings to dispatch,
    # e.g.: `hxhxmacros.ExternalMacros.external();some.pack.M.foo()`
    #
    # For bring-up we only support:
    # - `pack.Class.method()` (no args)
    # - `pack.Class.method(\"...\")` (one String literal arg)
    {
      echo "package hxhxmacrohost;"
      echo ""
      echo "class EntryPointsGen {"
      echo "  public static function run(expr:String):Null<String> {"
      echo "    if (expr == null) return null;"
      echo "    final e = StringTools.trim(expr);"
      echo "    return switch (e) {"

      IFS=';' read -r -a entries <<<"${HXHX_MACRO_HOST_ENTRYPOINTS}"
      for raw in "${entries[@]}"; do
        entry="$(trim_ws "$raw")"
        if [ -z "$entry" ]; then
          continue
        fi

        # Expect `pack.Class.method(...)`.
        if [[ "$entry" != *")" ]]; then
          echo "      // Skipping unsupported entry (expected call expression): $entry"
          continue
        fi

        call_prefix="${entry%%(*}"
        args_inside="${entry#*(}"
        args_inside="${args_inside%)}"

        cls="${call_prefix%.*}"
        meth="${call_prefix##*.}"
        if [ -z "$cls" ] || [ -z "$meth" ] || [ "$cls" = "$call_prefix" ]; then
          echo "      // Skipping malformed entry: $entry"
          continue
        fi

        args_inside="$(trim_ws "$args_inside")"
        call_args=""
        if [ -n "$args_inside" ]; then
          # Bring-up rung: only support a single String literal argument.
          #
          # Examples:
          # - foo.Bar.baz(\"ok\")
          # - foo.Bar.baz('ok')  (accepted by Haxe for string literals)
          if [[ ( "$args_inside" == \"*\" && "$args_inside" == *\" ) || ( "$args_inside" == \'*\' && "$args_inside" == *\' ) ]]; then
            call_args="$args_inside"
          else
            echo "      // Skipping unsupported entry (expected 0 args or 1 string literal arg): $entry"
            continue
          fi
        fi

        entry_escaped="$(escape_hx_string "$entry")"

        # Emit case. We reference the method directly so Haxe resolves it statically.
        # We intentionally only dispatch exact strings for auditability.
        #
        # We discard the entrypoint return value and return `"ok"` so we can support both:
        # - `Void` macro entrypoints like `Macro.init()`
        # - `String` macro entrypoints used for deterministic bring-up reports
        if [ -n "$call_args" ]; then
          echo "      case \"${entry_escaped}\": { ${cls}.${meth}(${call_args}); \"ok\"; }"
        else
          echo "      case \"${entry_escaped}\": { ${cls}.${meth}(); \"ok\"; }"
        fi
      done

      echo "      case _: null;"
      echo "    }"
      echo "  }"
      echo "}"
    } >"$gen_file"

    extra+=("-cp" "$gen_cp" "-D" "hxhx_entrypoints")
  fi

  if [ -n "${HXHX_MACRO_HOST_EXTRA_CP:-}" ]; then
    IFS=':' read -r -a cps <<<"${HXHX_MACRO_HOST_EXTRA_CP}"
    for cp in "${cps[@]}"; do
      cp="$(normalize_cp "$cp")"
      if [ -n "$cp" ]; then
        extra+=("-cp" "$cp")
      fi
    done
  fi
  cmd=("$HAXE_BIN" build.hxml -D ocaml_build=native)
  if [ "${#extra[@]}" -gt 0 ]; then
    cmd+=("${extra[@]}")
  fi
  "${cmd[@]}"
)

BIN="$TOOL_DIR/out/_build/default/out.exe"
if [ ! -f "$BIN" ]; then
  echo "Missing built executable: $BIN" >&2
  exit 1
fi

echo "$BIN"
