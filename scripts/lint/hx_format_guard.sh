#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

if ! command -v haxelib >/dev/null 2>&1; then
	echo "[guard:hx-format] ERROR: haxelib is required." >&2
	exit 1
fi

if ! haxelib run formatter --help >/dev/null 2>&1; then
	echo "[guard:hx-format] ERROR: formatter haxelib is not installed." >&2
	echo "[guard:hx-format] Install it with: haxelib install formatter" >&2
	exit 1
fi

echo "[guard:hx-format] Checking Haxe formatting..."
haxelib run formatter -s packages -s test -s examples -s workloads --check

SENTINEL_FILE="packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx"
if [ -f "$SENTINEL_FILE" ]; then
	tmp_dir="$(mktemp -d)"
	tmp_file="$tmp_dir/$(basename "$SENTINEL_FILE")"
	cp "$SENTINEL_FILE" "$tmp_file"
	haxelib run formatter -s "$tmp_file" >/dev/null
	hash_first="$(shasum "$tmp_file" | awk '{print $1}')"
	haxelib run formatter -s "$tmp_file" >/dev/null
	hash_second="$(shasum "$tmp_file" | awk '{print $1}')"
	rm -rf "$tmp_dir"

	if [ "$hash_first" != "$hash_second" ]; then
		echo "[guard:hx-format] ERROR: formatter output is nondeterministic for $SENTINEL_FILE" >&2
		exit 1
	fi
fi

echo "[guard:hx-format] OK: Haxe formatting is clean."
