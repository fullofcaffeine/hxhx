#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ci/extract-stage0-peak-rss.sh <stage0-log-file>
  cat <stage0-log-file> | bash scripts/ci/extract-stage0-peak-rss.sh -

Prints the peak `tree_rss=<n>MB` value seen in Stage0 heartbeat lines.
Prints `0` when no `tree_rss` samples are present.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

input="${1:-}"
if [ -z "$input" ]; then
  usage >&2
  exit 2
fi

tmp_input=""
if [ "$input" = "-" ]; then
  tmp_input="$(mktemp)"
  cat >"$tmp_input"
  input="$tmp_input"
fi

if [ ! -f "$input" ]; then
  echo "Missing input log file: $input" >&2
  rm -f "$tmp_input"
  exit 2
fi

peak="$(
  if command -v rg >/dev/null 2>&1; then
    rg -o 'tree_rss=[0-9]+MB' "$input" || true
  else
    grep -Eo 'tree_rss=[0-9]+MB' "$input" || true
  fi \
    | sed -e 's/tree_rss=//' -e 's/MB$//' \
    | sort -n \
    | tail -n 1
)"

if [ -z "$peak" ]; then
  peak="0"
fi

echo "$peak"
rm -f "$tmp_input"
