#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/dev/clean-artifacts.sh [--safe|--deep|--tmp-only] [--dry-run] [--older-than <duration>] [--yes]

Modes:
  --safe       Remove repo-local transient build/test artifacts (default).
  --deep       Includes heavy bootstrap build caches (requires --yes in non-interactive shells).
  --tmp-only   Remove stale stage0 temp logs from OS temp directories.

Flags:
  --dry-run            Print candidates and estimated reclaim size without deleting.
  --older-than <dur>   Age threshold for temp-log cleanup (default: 24h). Formats: 90m, 12h, 7d.
  --yes                Skip interactive confirmation for deep mode.
  -h, --help           Show this help.
USAGE
}

human_from_kb() {
  local kb="$1"
  awk -v kb="$kb" 'BEGIN {
    if (kb < 1024) { printf "%.0fKB", kb; exit }
    mb = kb / 1024.0
    if (mb < 1024) { printf "%.1fMB", mb; exit }
    gb = mb / 1024.0
    printf "%.2fGB", gb
  }'
}

duration_to_minutes() {
  local duration="$1"
  if [[ "$duration" =~ ^[0-9]+$ ]]; then
    echo "$duration"
    return 0
  fi
  if [[ "$duration" =~ ^([0-9]+)([mhd])$ ]]; then
    local value="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      m) echo "$value" ;;
      h) echo "$((value * 60))" ;;
      d) echo "$((value * 60 * 24))" ;;
      *)
        return 1
        ;;
    esac
    return 0
  fi
  return 1
}

mtime_epoch() {
  local path="$1"
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
    return 0
  fi
  stat -c %Y "$path"
}

MODE="safe"
DRY_RUN=0
YES=0
OLDER_THAN="24h"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --safe)
      MODE="safe"
      ;;
    --deep)
      MODE="deep"
      ;;
    --tmp-only)
      MODE="tmp-only"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --older-than)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --older-than" >&2
        exit 1
      fi
      OLDER_THAN="$2"
      shift
      ;;
    --yes)
      YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANDIDATES="$(mktemp -t hxhx-clean-candidates.XXXXXX)"
UNIQUE_CANDIDATES="$(mktemp -t hxhx-clean-candidates-uniq.XXXXXX)"
trap 'rm -f "$CANDIDATES" "$UNIQUE_CANDIDATES"' EXIT

add_path_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    printf '%s\n' "$path" >>"$CANDIDATES"
  fi
}

collect_safe_candidates() {
  add_path_if_exists "$ROOT/out"
  add_path_if_exists "$ROOT/tmp_stat_portable.txt"
  add_path_if_exists "$ROOT/test/upstream_min_repro"
  add_path_if_exists "$ROOT/packages/hxhx/out"
  add_path_if_exists "$ROOT/tools/hxhx-macro-host/out"

  if [[ -d "$ROOT" ]]; then
    find "$ROOT" -mindepth 1 -maxdepth 1 -type d \
      \( -name 'out_ocaml*' -o -name 'dump_*' -o -name 'dump_out_*' \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  if [[ -d "$ROOT/examples" ]]; then
    find "$ROOT/examples" -type d \
      \( -name out -o -name 'out_tmp*' -o -name 'out_stage*' \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  if [[ -d "$ROOT/workloads" ]]; then
    find "$ROOT/workloads" -type d \
      \( -name out -o -name 'out_tmp*' -o -name 'out_stage*' \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  if [[ -d "$ROOT/packages" ]]; then
    find "$ROOT/packages" -type d \
      \( -name out -o -name 'out_tmp*' -o -name 'out_stage*' \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  if [[ -d "$ROOT/tools" ]]; then
    find "$ROOT/tools" -type d \
      \( -name out -o -name 'out_tmp*' -o -name 'out_stage*' \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  if [[ -d "$ROOT/test/portable" ]]; then
    find "$ROOT/test/portable" -type d -name out -print >>"$CANDIDATES" 2>/dev/null || true
    find "$ROOT/test/portable" -type f \
      \( -name stdout.txt -o -name stderr.txt \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi
}

collect_deep_candidates() {
  collect_safe_candidates
  add_path_if_exists "$ROOT/packages/hxhx/bootstrap_out/_build"
  add_path_if_exists "$ROOT/tools/hxhx-macro-host/bootstrap_out/_build"

  if [[ -d "$ROOT/packages/hxhx/bootstrap_out" ]]; then
    find "$ROOT/packages/hxhx/bootstrap_out" -maxdepth 1 -type f -name '*.install' -print >>"$CANDIDATES" 2>/dev/null || true
  fi
  if [[ -d "$ROOT/tools/hxhx-macro-host/bootstrap_out" ]]; then
    find "$ROOT/tools/hxhx-macro-host/bootstrap_out" -maxdepth 1 -type f -name '*.install' -print >>"$CANDIDATES" 2>/dev/null || true
  fi
}

collect_tmp_candidates() {
  local threshold_minutes
  threshold_minutes="$(duration_to_minutes "$OLDER_THAN")" || {
    echo "Invalid --older-than value: $OLDER_THAN (expected like 90m, 12h, 7d)" >&2
    exit 1
  }
  local now_epoch
  now_epoch="$(date +%s)"

  local roots=()
  roots+=("/tmp")
  if [[ -n "${TMPDIR:-}" ]]; then
    roots+=("$TMPDIR")
  fi
  roots+=("/var/folders")

  for root in "${roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      continue
    fi
    while IFS= read -r path; do
      if [[ -z "$path" ]]; then
        continue
      fi
      local mtime
      mtime="$(mtime_epoch "$path" 2>/dev/null || true)"
      if [[ -z "$mtime" ]]; then
        continue
      fi
      local age_minutes
      age_minutes=$(( (now_epoch - mtime) / 60 ))
      if [[ "$age_minutes" -ge "$threshold_minutes" ]]; then
        printf '%s\n' "$path" >>"$CANDIDATES"
      fi
    done < <(
      find "$root" -type f \
        \( -name 'hxhx-stage0-emit*.log*' -o -name 'hxhx-stage0-build*.log*' \) \
        -print 2>/dev/null || true
    )
  done
}

case "$MODE" in
  safe)
    collect_safe_candidates
    ;;
  deep)
    collect_deep_candidates
    ;;
  tmp-only)
    collect_tmp_candidates
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 1
    ;;
esac

sort -u "$CANDIDATES" >"$UNIQUE_CANDIDATES"

if [[ ! -s "$UNIQUE_CANDIDATES" ]]; then
  echo "No cleanup candidates found (mode=$MODE)."
  exit 0
fi

count="$(wc -l <"$UNIQUE_CANDIDATES" | tr -d ' ')"
total_kb=0
while IFS= read -r path; do
  if [[ -e "$path" ]]; then
    path_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    if [[ -n "$path_kb" ]]; then
      total_kb=$((total_kb + path_kb))
    fi
  fi
done <"$UNIQUE_CANDIDATES"

echo "Cleanup mode: $MODE"
echo "Candidates: $count"
echo "Estimated reclaim: $(human_from_kb "$total_kb")"
echo "Sample candidates:"
head -n 20 "$UNIQUE_CANDIDATES"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry-run only; no files deleted."
  exit 0
fi

if [[ "$MODE" == "deep" && "$YES" -ne 1 ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Proceed with deep cleanup? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "Canceled."
      exit 0
    fi
  else
    echo "Deep cleanup in non-interactive mode requires --yes." >&2
    exit 1
  fi
fi

deleted=0
while IFS= read -r path; do
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    deleted=$((deleted + 1))
  fi
done <"$UNIQUE_CANDIDATES"

echo "Deleted: $deleted"
echo "Cleanup complete."
