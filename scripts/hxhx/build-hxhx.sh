#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_CONNECT="${HAXE_CONNECT:-}"
HXHX_FORCE_STAGE0="${HXHX_FORCE_STAGE0:-}"
HXHX_STAGE0_PROGRESS="${HXHX_STAGE0_PROGRESS:-0}"
HXHX_STAGE0_PROFILE="${HXHX_STAGE0_PROFILE:-0}"
HXHX_STAGE0_PROFILE_DETAIL="${HXHX_STAGE0_PROFILE_DETAIL:-0}"
HXHX_STAGE0_PROFILE_CLASS="${HXHX_STAGE0_PROFILE_CLASS:-}"
HXHX_STAGE0_PROFILE_FIELD="${HXHX_STAGE0_PROFILE_FIELD:-}"
HXHX_STAGE0_OCAML_BUILD="${HXHX_STAGE0_OCAML_BUILD:-byte}"
HXHX_STAGE0_PREFER_NATIVE="${HXHX_STAGE0_PREFER_NATIVE:-0}"
HXHX_STAGE0_TIMES="${HXHX_STAGE0_TIMES:-0}"
HXHX_STAGE0_VERBOSE="${HXHX_STAGE0_VERBOSE:-0}"
HXHX_STAGE0_DISABLE_PREPASSES="${HXHX_STAGE0_DISABLE_PREPASSES:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HXHX_DIR="$ROOT/packages/hxhx"
BOOTSTRAP_DIR="$HXHX_DIR/bootstrap_out"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx build: dune/ocamlc not found on PATH."
  exit 0
fi

if [ ! -d "$HXHX_DIR" ]; then
  echo "Missing hxhx package directory: $HXHX_DIR" >&2
  exit 1
fi

if [ -z "$HXHX_FORCE_STAGE0" ] && [ -d "$BOOTSTRAP_DIR" ] && [ -f "$BOOTSTRAP_DIR/dune" ]; then
  (
    cd "$BOOTSTRAP_DIR"
    if [ "${HXHX_BOOTSTRAP_PREFER_NATIVE:-0}" = "1" ]; then
      dune build ./out.exe || dune build ./out.bc
    else
      dune build ./out.bc || dune build ./out.exe
    fi
  )

  BIN_EXE="$BOOTSTRAP_DIR/_build/default/out.exe"
  BIN_BC="$BOOTSTRAP_DIR/_build/default/out.bc"
  if [ -f "$BIN_EXE" ]; then
    echo "$BIN_EXE"
    exit 0
  fi
  if [ -f "$BIN_BC" ]; then
    echo "$BIN_BC"
    exit 0
  fi

  echo "Missing built executable: $BIN_EXE (native) or $BIN_BC (bytecode)" >&2
  exit 1
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

(
  cd "$HXHX_DIR"
  build_mode="$HXHX_STAGE0_OCAML_BUILD"
  if [ "$HXHX_STAGE0_PREFER_NATIVE" = "1" ]; then
    build_mode="native"
  fi

  rm -rf out
  mkdir -p out

  haxe_args=(build.hxml -D "ocaml_build=$build_mode")
  if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
    haxe_args+=(-v)
  fi
  if [ -n "$HAXE_CONNECT" ]; then
    haxe_args+=(--connect "$HAXE_CONNECT")
  fi
  if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_progress)
  fi
  if [ "$HXHX_STAGE0_PROFILE" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_profile)
  fi
  if [ "$HXHX_STAGE0_PROFILE_DETAIL" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_profile_detail)
  fi
  if [ -n "$HXHX_STAGE0_PROFILE_CLASS" ]; then
    haxe_args+=(-D "reflaxe_ocaml_profile_class=$HXHX_STAGE0_PROFILE_CLASS")
  fi
  if [ -n "$HXHX_STAGE0_PROFILE_FIELD" ]; then
    haxe_args+=(-D "reflaxe_ocaml_profile_field=$HXHX_STAGE0_PROFILE_FIELD")
  fi
  if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
  fi
  if [ "$HXHX_STAGE0_TIMES" = "1" ]; then
    haxe_args+=(--times)
  fi

  if ! "$HAXE_BIN" "${haxe_args[@]}"; then
    if [ "$build_mode" = "native" ]; then
      echo "hxhx stage0 build: native failed; retrying bytecode (expected on some platforms; set HXHX_STAGE0_OCAML_BUILD=byte to skip native attempts)." >&2
      build_mode="byte"
      rm -rf out
      mkdir -p out
      haxe_args=(build.hxml -D "ocaml_build=$build_mode")
      if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
        haxe_args+=(-v)
      fi
      if [ -n "$HAXE_CONNECT" ]; then
        haxe_args+=(--connect "$HAXE_CONNECT")
      fi
      if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_progress)
      fi
      if [ "$HXHX_STAGE0_PROFILE" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_profile)
      fi
      if [ "$HXHX_STAGE0_PROFILE_DETAIL" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_profile_detail)
      fi
      if [ -n "$HXHX_STAGE0_PROFILE_CLASS" ]; then
        haxe_args+=(-D "reflaxe_ocaml_profile_class=$HXHX_STAGE0_PROFILE_CLASS")
      fi
      if [ -n "$HXHX_STAGE0_PROFILE_FIELD" ]; then
        haxe_args+=(-D "reflaxe_ocaml_profile_field=$HXHX_STAGE0_PROFILE_FIELD")
      fi
      if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
      fi
      if [ "$HXHX_STAGE0_TIMES" = "1" ]; then
        haxe_args+=(--times)
      fi
      "$HAXE_BIN" "${haxe_args[@]}"
    else
      exit 1
    fi
  fi
)

BIN_EXE="$HXHX_DIR/out/_build/default/out.exe"
BIN_BC="$HXHX_DIR/out/_build/default/out.bc"
if [ -f "$BIN_EXE" ]; then
  echo "$BIN_EXE"
  exit 0
fi
if [ -f "$BIN_BC" ]; then
  echo "$BIN_BC"
  exit 0
fi

echo "Missing built executable: $BIN_EXE (native) or $BIN_BC (bytecode)" >&2
exit 1
