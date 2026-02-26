#!/usr/bin/env bash
set -euo pipefail

ocamlopt_bin="${HXHX_OCAMLOPT_BASE:-ocamlopt}"

args=("$@")

has_arg() {
  local needle="$1"
  local value
  for value in "${args[@]}"; do
    if [ "$value" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

contains_compile_only_flag() {
  local value
  for value in "${args[@]}"; do
    case "$value" in
      -c|-i|-S|-stop-after)
        return 0
        ;;
    esac
  done
  return 1
}

first_module_index() {
  local i=0
  local value
  for value in "${args[@]}"; do
    case "$value" in
      *.cmx|*.cmo|*.ml)
        echo "$i"
        return 0
        ;;
    esac
    i=$((i + 1))
  done
  echo "${#args[@]}"
}

index_of_arg() {
  local needle="$1"
  local i=0
  local value
  for value in "${args[@]}"; do
    if [ "$value" = "$needle" ]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  echo "-1"
}

insert_index_result=0

insert_before_modules() {
  local token="$1"
  local index="$2"
  if has_arg "$token"; then
    insert_index_result="$index"
    return 0
  fi
  if [ "$index" -ge "${#args[@]}" ]; then
    args+=("$token")
    insert_index_result="${#args[@]}"
    return 0
  fi
  args=("${args[@]:0:$index}" "$token" "${args[@]:$index}")
  insert_index_result=$((index + 1))
}

if ! contains_compile_only_flag; then
  if ! has_arg "-thread"; then
    args=("-thread" "${args[@]}")
  fi
  module_index="$(first_module_index)"
  lib_insert_index="$module_index"
  unix_index="$(index_of_arg "unix.cmxa")"
  str_index="$(index_of_arg "str.cmxa")"
  if [ "$str_index" -ge 0 ] && [ "$str_index" -lt "$module_index" ]; then
    lib_insert_index=$((str_index + 1))
  elif [ "$unix_index" -ge 0 ] && [ "$unix_index" -lt "$module_index" ]; then
    lib_insert_index=$((unix_index + 1))
  fi
  insert_before_modules "threads.cmxa" "$lib_insert_index"
  module_index="$insert_index_result"
  insert_before_modules "dynlink.cmxa" "$module_index"
  module_index="$insert_index_result"
fi

if ! has_arg "+threads"; then
  args=("-I" "+threads" "${args[@]}")
fi
if ! has_arg "+dynlink"; then
  args=("-I" "+dynlink" "${args[@]}")
fi

if [ "${HXHX_OCAMLOPT_DEBUG:-0}" = "1" ]; then
  printf 'ocamlopt wrapper command: %q' "$ocamlopt_bin" >&2
  for arg in "${args[@]}"; do
    printf ' %q' "$arg" >&2
  done
  printf '\n' >&2
fi

exec "$ocamlopt_bin" "${args[@]}"
