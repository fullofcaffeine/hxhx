#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/dev/clean-artifacts.sh [--safe|--deep|--tmp-only|--emergency] [--dry-run] [--older-than <duration>] [--artifacts-older-than <duration>] [--yes] [--verbose] [--max-sample <n>]

Modes:
  --safe       Remove repo-local transient build/test artifacts (default).
  --deep       Includes heavy bootstrap build caches (requires --yes in non-interactive shells).
  --tmp-only   Remove stale stage0 temp logs from OS temp directories.
  --emergency  Reclaim only stale, unprotected .artifacts entries without allocating inventory files.

Flags:
  --dry-run            Print candidates and estimated reclaim size without deleting.
  --older-than <dur>   Age threshold for temp-log cleanup (default: 24h). Formats: 90m, 12h, 7d.
  --artifacts-older-than <dur>
                       Age threshold for ignored .artifacts entries (default: 7d).
  --yes                Skip interactive confirmation for deep mode.
  --verbose            Print all candidates (largest first) and per-delete progress.
  --max-sample <n>     Number of candidates to preview when not verbose (default: 20).
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
ARTIFACTS_OLDER_THAN="7d"
VERBOSE=0
MAX_SAMPLE=20

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
    --emergency)
      MODE="emergency"
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
    --artifacts-older-than)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --artifacts-older-than" >&2
        exit 1
      fi
      ARTIFACTS_OLDER_THAN="$2"
      shift
      ;;
    --yes)
      YES=1
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --max-sample)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --max-sample" >&2
        exit 1
      fi
      MAX_SAMPLE="$2"
      shift
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

if ! [[ "$MAX_SAMPLE" =~ ^[0-9]+$ ]] || [[ "$MAX_SAMPLE" -lt 1 ]]; then
  echo "Invalid --max-sample value: $MAX_SAMPLE (expected positive integer)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_BUILD_PID_FILE=".hxhx-bootstrap-build.pid"
MACRO_HOST_BUILD_PID_SUFFIX=".hxhx-macro-host-build.pid"
MACRO_HOST_GENERATED_INPUT_SUFFIX=".hxhx-macro-host-input"
ARTIFACT_RETAIN_MARKER=".hxhx-clean-retain"
ARTIFACT_ACTIVE_PID_MARKER=".hxhx-clean-active.pid"
ARTIFACTS_ROOT="$ROOT/.artifacts"
ARTIFACT_THRESHOLD_MINUTES="$(duration_to_minutes "$ARTIFACTS_OLDER_THAN")" || {
  echo "Invalid --artifacts-older-than value: $ARTIFACTS_OLDER_THAN (expected like 90m, 12h, 7d)" >&2
  exit 1
}
CANDIDATES=""
UNIQUE_CANDIDATES=""
SIZE_REPORT=""

cleanup_inventory_files() {
  local file=""
  for file in "$CANDIDATES" "$UNIQUE_CANDIDATES" "$SIZE_REPORT"; do
    if [[ -n "$file" && -e "$file" ]]; then
      rm -f "$file"
    fi
  done
}
trap cleanup_inventory_files EXIT
GIT_AVAILABLE=0
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_AVAILABLE=1
fi

to_repo_relative() {
  local path="$1"
  if [[ "$path" == "$ROOT" ]]; then
    echo "."
    return 0
  fi
  if [[ "$path" == "$ROOT/"* ]]; then
    echo "${path#"$ROOT/"}"
    return 0
  fi
  return 1
}

is_tracked_path() {
  local path="$1"
  if [[ "$GIT_AVAILABLE" -ne 1 ]]; then
    return 1
  fi
  local rel
  rel="$(to_repo_relative "$path")" || return 1
  git -C "$ROOT" ls-files -- "$rel" | grep -Fxq "$rel"
}

dir_has_tracked_entries() {
  local path="$1"
  if [[ "$GIT_AVAILABLE" -ne 1 || ! -d "$path" ]]; then
    return 1
  fi
  local rel
  rel="$(to_repo_relative "$path")" || return 1
  [[ -n "$(git -C "$ROOT" ls-files -- "$rel")" ]]
}

add_path_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    printf '%s\n' "$path" >>"$CANDIDATES"
  fi
}

build_pid_file_is_active() {
  local pid_file="${1:-}"
  local owner_pid=""

  if [[ -z "$pid_file" || ! -f "$pid_file" ]]; then
    return 1
  fi
  owner_pid="$(head -n 1 "$pid_file" 2>/dev/null | tr -d '[:space:]' || true)"
  case "$owner_pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$owner_pid" >/dev/null 2>&1
}

build_dir_is_active() {
  local dir="${1:-}"
  local pid_file_name="${2:-}"

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    return 1
  fi
  build_pid_file_is_active "$dir/$pid_file_name"
}

bootstrap_build_dir_is_active() {
  build_dir_is_active "${1:-}" "$BOOTSTRAP_BUILD_PID_FILE"
}

macro_host_build_dir_is_active() {
  local dir="${1:-}"
  if [[ -z "$dir" ]]; then
    return 1
  fi
  build_pid_file_is_active "${dir}${MACRO_HOST_BUILD_PID_SUFFIX}"
}

# Returns success and a plain-language reason when an evidence tree must stay.
# A stale tree is removable only when every descendant is old and neither a
# reviewer retention marker nor a live producer PID owns it.
artifact_protection_reason() {
  local path="${1:-}"
  local marker=""
  local mtime=""
  local entry_mtime=""
  local now_epoch=""
  local age_minutes=""
  local entry_age_minutes=""

  if [[ -z "$path" || ! -e "$path" ]]; then
    echo "missing path"
    return 0
  fi

  mtime="$(mtime_epoch "$path" 2>/dev/null || true)"
  if [[ -z "$mtime" ]]; then
    echo "timestamp unavailable"
    return 0
  fi
  now_epoch="$(date +%s)"
  age_minutes=$(( (now_epoch - mtime) / 60 ))
  if [[ "$age_minutes" -lt "$ARTIFACT_THRESHOLD_MINUTES" ]]; then
    echo "newer than $ARTIFACTS_OLDER_THAN"
    return 0
  fi

  if ! find "$path" -mindepth 1 -print >/dev/null 2>&1; then
    echo "evidence tree cannot be inspected safely"
    return 0
  fi
  while IFS= read -r marker; do
    entry_mtime="$(mtime_epoch "$marker" 2>/dev/null || true)"
    if [[ -z "$entry_mtime" ]]; then
      echo "descendant timestamp unavailable at $marker"
      return 0
    fi
    entry_age_minutes=$(( (now_epoch - entry_mtime) / 60 ))
    if [[ "$entry_age_minutes" -lt "$ARTIFACT_THRESHOLD_MINUTES" ]]; then
      echo "contains evidence newer than $ARTIFACTS_OLDER_THAN"
      return 0
    fi
  done < <(find "$path" -mindepth 1 -print 2>/dev/null || true)

  marker="$(find "$path" -name "$ARTIFACT_RETAIN_MARKER" -print -quit 2>/dev/null || true)"
  if [[ -n "$marker" ]]; then
    echo "explicit retain marker at $marker"
    return 0
  fi

  while IFS= read -r marker; do
    if build_pid_file_is_active "$marker"; then
      echo "live owner PID in $marker"
      return 0
    fi
  done < <(find "$path" -type f -name "$ARTIFACT_ACTIVE_PID_MARKER" -print 2>/dev/null || true)
  return 1
}

# Adds only stale, unowned top-level evidence trees to normal cleanup. Keeping
# the unit at the top-level directory makes review packages and their manifests
# expire together instead of leaving partial evidence behind.
collect_artifact_candidates() {
  local path=""
  local reason=""
  local path_kb=0
  local eligible_count=0
  local eligible_kb=0
  local protected_count=0
  local protected_kb=0
  if [[ ! -d "$ARTIFACTS_ROOT" ]]; then
    return 0
  fi
  while IFS= read -r path; do
    path_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$path_kb" ]]; then
      path_kb=0
    fi
    if reason="$(artifact_protection_reason "$path")"; then
      protected_count=$((protected_count + 1))
      protected_kb=$((protected_kb + path_kb))
      if [[ "$VERBOSE" -eq 1 ]]; then
        echo "Protected artifact: $(human_from_kb "$path_kb")  $path ($reason)"
      fi
      continue
    fi
    eligible_count=$((eligible_count + 1))
    eligible_kb=$((eligible_kb + path_kb))
    printf '%s\n' "$path" >>"$CANDIDATES"
  done < <(find "$ARTIFACTS_ROOT" -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)
  echo "Artifact evidence eligible for cleanup: $eligible_count ($(human_from_kb "$eligible_kb"))"
  echo "Artifact evidence protected: $protected_count ($(human_from_kb "$protected_kb"))"
}

# Provides a deliberately narrow recovery path when mktemp cannot allocate the
# normal sorted inventory. It never leaves this repository's .artifacts root
# and repeats the same age/ownership checks immediately before each deletion.
run_emergency_cleanup() {
  local path=""
  local reason=""
  local path_kb=0
  local candidates=0
  local candidate_kb=0
  local deleted=0
  local protected=0
  local protected_kb=0
  local reclaimed_kb=0

  echo "Cleanup mode: emergency"
  echo "Scope: stale, unprotected top-level entries under $ARTIFACTS_ROOT"
  echo "Age threshold: $ARTIFACTS_OLDER_THAN"
  if [[ ! -d "$ARTIFACTS_ROOT" ]]; then
    echo "No emergency cleanup candidates found."
    return 0
  fi

  while IFS= read -r path; do
    path_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$path_kb" ]]; then
      path_kb=0
    fi
    if reason="$(artifact_protection_reason "$path")"; then
      protected=$((protected + 1))
      protected_kb=$((protected_kb + path_kb))
      if [[ "$VERBOSE" -eq 1 ]]; then
        echo "Protected artifact: $(human_from_kb "$path_kb")  $path ($reason)"
      fi
      continue
    fi
    if is_tracked_path "$path" || { [[ -d "$path" ]] && dir_has_tracked_entries "$path"; }; then
      echo "Protected artifact: $path (tracked repository content)"
      protected=$((protected + 1))
      protected_kb=$((protected_kb + path_kb))
      continue
    fi
    candidates=$((candidates + 1))
    candidate_kb=$((candidate_kb + path_kb))
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "Would delete stale artifact: $(human_from_kb "$path_kb")  $path"
      continue
    fi
    if reason="$(artifact_protection_reason "$path")"; then
      echo "Protected artifact before deletion: $path ($reason)"
      continue
    fi
    echo "Deleting stale artifact: $(human_from_kb "$path_kb")  $path"
    rm -rf "$path"
    deleted=$((deleted + 1))
    reclaimed_kb=$((reclaimed_kb + path_kb))
  done < <(find "$ARTIFACTS_ROOT" -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)

  echo "Eligible stale artifact evidence: $candidates ($(human_from_kb "$candidate_kb"))"
  echo "Protected artifact evidence: $protected ($(human_from_kb "$protected_kb"))"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry-run only; no files deleted."
  else
    echo "Deleted: $deleted"
    echo "Actual reclaimed: $(human_from_kb "$reclaimed_kb")"
  fi
  echo "Emergency cleanup complete."
}

collect_safe_candidates() {
  local build_dir=""

  add_path_if_exists "$ROOT/out"
  add_path_if_exists "$ROOT/tmp_stat_portable.txt"
  add_path_if_exists "$ROOT/test/upstream_min_repro"
  add_path_if_exists "$ROOT/packages/hxhx/out"
  add_path_if_exists "$ROOT/packages/hxhx/bootstrap_work"
  add_path_if_exists "$ROOT/packages/hxhx/bootstrap_verify"
  add_path_if_exists "$ROOT/packages/hxhx-macro-host/out"

  if [[ -d "$ROOT/.tmp" ]]; then
    while IFS= read -r path; do
      if [[ -d "$path" ]] && ! macro_host_build_dir_is_active "$path"; then
        printf '%s\n' "$path" >>"$CANDIDATES"
        add_path_if_exists "${path}${MACRO_HOST_BUILD_PID_SUFFIX}"
      fi
    done < <(find "$ROOT/.tmp" -mindepth 1 -maxdepth 1 -type d -name 'hxhx-macro-host-build.*' ! -name "*${MACRO_HOST_GENERATED_INPUT_SUFFIX}" -print 2>/dev/null || true)
    while IFS= read -r path; do
      build_dir="${path%"$MACRO_HOST_GENERATED_INPUT_SUFFIX"}"
      if ! macro_host_build_dir_is_active "$build_dir"; then
        printf '%s\n' "$path" >>"$CANDIDATES"
      fi
    done < <(find "$ROOT/.tmp" -mindepth 1 -maxdepth 1 -type d -name "hxhx-macro-host-build.*${MACRO_HOST_GENERATED_INPUT_SUFFIX}" -print 2>/dev/null || true)
    while IFS= read -r path; do
      build_dir="${path%"$MACRO_HOST_BUILD_PID_SUFFIX"}"
      if ! macro_host_build_dir_is_active "$build_dir"; then
        printf '%s\n' "$path" >>"$CANDIDATES"
      fi
    done < <(find "$ROOT/.tmp" -mindepth 1 -maxdepth 1 -type f -name "hxhx-macro-host-build.*${MACRO_HOST_BUILD_PID_SUFFIX}" -print 2>/dev/null || true)
  fi

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

  if [[ -d "$ROOT/test" ]]; then
    find "$ROOT/test" \
      \( -path "$ROOT/test/snapshot" -o -path "$ROOT/test/portable" \) -prune -o \
      -type d \( -name out -o -name 'out_tmp*' -o -name 'out_stage*' \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  if [[ -d "$ROOT/test/portable" ]]; then
    find "$ROOT/test/portable" -type d -name out -print >>"$CANDIDATES" 2>/dev/null || true
    find "$ROOT/test/portable" -type f \
      \( -name stdout.txt -o -name stderr.txt \) \
      -print >>"$CANDIDATES" 2>/dev/null || true
  fi

  collect_artifact_candidates
}

collect_deep_candidates() {
  collect_safe_candidates
  add_path_if_exists "$ROOT/packages/hxhx/bootstrap_out/_build"
  add_path_if_exists "$ROOT/packages/hxhx-macro-host/bootstrap_out/_build"

  if [[ -d "$ROOT/.tmp" ]]; then
    while IFS= read -r path; do
      if [[ -d "$path" ]] && ! bootstrap_build_dir_is_active "$path"; then
        printf '%s\n' "$path" >>"$CANDIDATES"
      fi
    done < <(find "$ROOT/.tmp" -mindepth 1 -maxdepth 1 -type d -name 'hxhx-bootstrap-build.*' -print 2>/dev/null || true)
  fi

  if [[ -d "$ROOT/packages/hxhx/bootstrap_out" ]]; then
    find "$ROOT/packages/hxhx/bootstrap_out" -maxdepth 1 -type f -name '*.install' -print >>"$CANDIDATES" 2>/dev/null || true
  fi
  if [[ -d "$ROOT/packages/hxhx-macro-host/bootstrap_out" ]]; then
    find "$ROOT/packages/hxhx-macro-host/bootstrap_out" -maxdepth 1 -type f -name '*.install' -print >>"$CANDIDATES" 2>/dev/null || true
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

if [[ "$MODE" == "emergency" ]]; then
  run_emergency_cleanup
  exit 0
fi

INVENTORY_TMP_ROOT="${TMPDIR:-/tmp}"
INVENTORY_TMP_ROOT="${INVENTORY_TMP_ROOT%/}"
if ! CANDIDATES="$(mktemp "$INVENTORY_TMP_ROOT/hxhx-clean-candidates.XXXXXX")"; then
  echo "Cleanup could not allocate its candidate inventory." >&2
  echo "Run 'npm run clean:emergency' to reclaim stale .artifacts entries without temporary inventory files." >&2
  exit 1
fi
if ! UNIQUE_CANDIDATES="$(mktemp "$INVENTORY_TMP_ROOT/hxhx-clean-candidates-uniq.XXXXXX")"; then
  echo "Cleanup could not allocate its deduplicated candidate inventory." >&2
  echo "Run 'npm run clean:emergency' to reclaim stale .artifacts entries without temporary inventory files." >&2
  exit 1
fi
if ! SIZE_REPORT="$(mktemp "$INVENTORY_TMP_ROOT/hxhx-clean-size-report.XXXXXX")"; then
  echo "Cleanup could not allocate its size report." >&2
  echo "Run 'npm run clean:emergency' to reclaim stale .artifacts entries without temporary inventory files." >&2
  exit 1
fi

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
    if [[ -z "$path_kb" ]]; then
      path_kb=0
    fi
    total_kb=$((total_kb + path_kb))
    printf '%s\t%s\n' "$path_kb" "$path" >>"$SIZE_REPORT"
  fi
done <"$UNIQUE_CANDIDATES"

print_candidates() {
  if [[ ! -s "$SIZE_REPORT" ]]; then
    return
  fi
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "Candidates (largest first):"
    while IFS=$'\t' read -r kb path; do
      echo "  - $(human_from_kb "$kb")  $path"
    done < <(sort -nr "$SIZE_REPORT")
    return
  fi

  echo "Sample candidates (largest first):"
  shown=0
  while IFS=$'\t' read -r kb path; do
    echo "  - $(human_from_kb "$kb")  $path"
    shown=$((shown + 1))
    if [[ "$shown" -ge "$MAX_SAMPLE" ]]; then
      break
    fi
  done < <(sort -nr "$SIZE_REPORT")
  if [[ "$count" -gt "$MAX_SAMPLE" ]]; then
    echo "  ... and $((count - MAX_SAMPLE)) more (use --verbose to list all)"
  fi
}

echo "Cleanup mode: $MODE"
echo "Candidates: $count"
echo "Estimated reclaim: $(human_from_kb "$total_kb")"
print_candidates

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
deleted_kb=0
skipped_tracked=0
skipped_protected=0
while IFS= read -r path; do
  if [[ -e "$path" ]]; then
    if [[ "$path" == "$ARTIFACTS_ROOT/"* ]]; then
      if reason="$(artifact_protection_reason "$path")"; then
        echo "Protected artifact before deletion: $path ($reason)"
        skipped_protected=$((skipped_protected + 1))
        continue
      fi
    fi
    path_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$path_kb" ]]; then
      path_kb=0
    fi
    if [[ "$VERBOSE" -eq 1 ]]; then
      next="$(($deleted + 1))"
      echo "[$next/$count] deleting $(human_from_kb "$path_kb"): $path"
    fi
    if [[ "$MODE" != "tmp-only" && -d "$path" ]] && dir_has_tracked_entries "$path"; then
      rel_path="$(to_repo_relative "$path")"
      if [[ "$VERBOSE" -eq 1 ]]; then
        echo "  preserving tracked contents via git clean: $path"
      fi
      if [[ "$path" == "$ARTIFACTS_ROOT/"* ]] && reason="$(artifact_protection_reason "$path")"; then
        echo "Protected artifact before deletion: $path ($reason)"
        skipped_protected=$((skipped_protected + 1))
        continue
      fi
      git -C "$ROOT" clean -fdx -- "$rel_path" >/dev/null 2>&1 || true
      after_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
      if [[ -z "$after_kb" ]]; then
        after_kb=0
      fi
      reclaimed_kb=$((path_kb - after_kb))
      if [[ "$reclaimed_kb" -lt 0 ]]; then
        reclaimed_kb=0
      fi
      if [[ "$reclaimed_kb" -gt 0 ]]; then
        deleted=$((deleted + 1))
        deleted_kb=$((deleted_kb + reclaimed_kb))
      fi
      continue
    fi

    if is_tracked_path "$path"; then
      if [[ "$VERBOSE" -eq 1 ]]; then
        echo "  skipping tracked path: $path"
      fi
      skipped_tracked=$((skipped_tracked + 1))
      continue
    fi

    if [[ "$path" == "$ARTIFACTS_ROOT/"* ]] && reason="$(artifact_protection_reason "$path")"; then
      echo "Protected artifact before deletion: $path ($reason)"
      skipped_protected=$((skipped_protected + 1))
      continue
    fi
    rm -rf "$path"
    deleted=$((deleted + 1))
    deleted_kb=$((deleted_kb + path_kb))
  fi
done <"$UNIQUE_CANDIDATES"

echo "Deleted: $deleted"
if [[ "$skipped_tracked" -gt 0 ]]; then
  echo "Skipped tracked paths: $skipped_tracked"
fi
if [[ "$skipped_protected" -gt 0 ]]; then
  echo "Skipped newly protected artifacts: $skipped_protected"
fi
echo "Actual reclaimed: $(human_from_kb "$deleted_kb")"
echo "Cleanup complete."
