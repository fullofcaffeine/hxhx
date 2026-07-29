#!/usr/bin/env bash
set -euo pipefail

# Proves that atomic generated-source publication and Dune's incremental cache
# have separate owners. Reflaxe replaces `out`; Dune keeps compiled state in a
# stable sibling and sees only the committed public workspace path.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/reflaxe_ocaml_transactional_dune"
WORK_DIR="$(mktemp -d "$ROOT/.reflaxe-ocaml-transactional-dune.XXXXXX")"
PROJECT_DIR="$WORK_DIR/project"
BUILD_DIR="$PROJECT_DIR/.out.reflaxe-ocaml-dune-build"
SOURCE_FILE="$PROJECT_DIR/src/Message.hx"

cleanup() {
	if [[ -d "$WORK_DIR" ]]; then
		find "$WORK_DIR" -depth -delete
	fi
}
trap cleanup EXIT

fail() {
	echo "reflaxe.ocaml transactional Dune test: $*" >&2
	exit 1
}

compile() {
	(
		cd "$PROJECT_DIR"
		haxe build.hxml -D reflaxe.dont_output_metadata_id
	)
}

source_bundle_revision() {
	node - "$PROJECT_DIR/out/ocaml_artifact_manifest.json" <<'NODE'
const fs = require('fs')
const manifest = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const revision = manifest?.summary?.sourceBundleRevision
if (typeof revision !== 'string' || !revision.startsWith('sha256:')) {
	throw new Error('missing source-bundle revision')
}
process.stdout.write(revision)
NODE
}

dune_milliseconds() {
	node - "$PROJECT_DIR/out/ocaml_build_timing_report.json" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const milliseconds = report?.summary?.duneBuildMilliseconds
if (!Number.isInteger(milliseconds) || milliseconds < 0) {
	throw new Error('missing non-negative Dune duration')
}
process.stdout.write(String(milliseconds))
NODE
}

artifact_path() {
	local name="$1"
	local matches
	matches="$(find "$BUILD_DIR" -type f -name "$name" -print)"
	[[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ]] \
		|| fail "expected one Dune artifact named $name, found: ${matches:-none}"
	printf '%s\n' "$matches"
}

mtime_milliseconds() {
	node - "$1" <<'NODE'
const fs = require('fs')
process.stdout.write(String(Math.floor(fs.statSync(process.argv[2]).mtimeMs)))
NODE
}

replace_source() {
	local expected="$1"
	local replacement="$2"
	node - "$SOURCE_FILE" "$expected" "$replacement" <<'NODE'
const fs = require('fs')
const [sourcePath, expected, replacement] = process.argv.slice(2)
const source = fs.readFileSync(sourcePath, 'utf8')
if (source.split(expected).length !== 2) {
	throw new Error(`expected exactly one ${JSON.stringify(expected)} in ${sourcePath}`)
}
fs.writeFileSync(sourcePath, source.replace(expected, replacement))
NODE
}

mkdir -p "$PROJECT_DIR"
cp "$FIXTURE/build.hxml" "$PROJECT_DIR/build.hxml"
cp -R "$FIXTURE/src" "$PROJECT_DIR/src"

compile
cold_dune_ms="$(dune_milliseconds)"
[[ -d "$BUILD_DIR" ]] || fail "Dune did not create the stable external build directory"
[[ ! -e "$PROJECT_DIR/out/_build" ]] || fail "Dune state leaked back into transactional generated output"
main_cmx="$(artifact_path main.cmx)"
message_cmx="$(artifact_path message.cmx)"
executable="$BUILD_DIR/default/out.exe"
[[ -f "$executable" ]] || fail "Dune did not produce the fixture executable"
revision_a="$(source_bundle_revision)"
main_a="$(mtime_milliseconds "$main_cmx")"
message_a="$(mtime_milliseconds "$message_cmx")"
executable_a="$(mtime_milliseconds "$executable")"

sleep 1
compile
warm_dune_ms="$(dune_milliseconds)"
[[ "$(source_bundle_revision)" = "$revision_a" ]] || fail "identical generated source changed its source-bundle revision"
[[ "$(mtime_milliseconds "$main_cmx")" = "$main_a" ]] || fail "identical publication recompiled Main"
[[ "$(mtime_milliseconds "$message_cmx")" = "$message_a" ]] || fail "identical publication recompiled Message"
[[ "$(mtime_milliseconds "$executable")" = "$executable_a" ]] || fail "identical publication relinked the executable"

replace_source "version-a" "version-b"
sleep 1
compile
edit_dune_ms="$(dune_milliseconds)"
revision_b="$(source_bundle_revision)"
[[ "$revision_b" != "$revision_a" ]] || fail "the leaf edit did not change generated-source identity"
main_b="$(mtime_milliseconds "$main_cmx")"
message_b="$(mtime_milliseconds "$message_cmx")"
executable_b="$(mtime_milliseconds "$executable")"
[[ "$main_b" = "$main_a" ]] || fail "an implementation-only Message edit unnecessarily recompiled Main"
(( message_b > message_a )) || fail "the Message edit did not rebuild Message"
(( executable_b > executable_a )) || fail "the Message edit did not relink the executable"

replace_source "version-b" "version-c"
if (
	cd "$PROJECT_DIR"
	haxe build.hxml -D reflaxe.dont_output_metadata_id -D reflaxe_output_transaction_test_fail_before_commit
) >"$WORK_DIR/expected-publication-failure.log" 2>&1; then
	fail "the injected pre-publication failure unexpectedly succeeded"
fi
[[ "$(source_bundle_revision)" = "$revision_b" ]] || fail "failed publication replaced the prior public source tree"
[[ "$(mtime_milliseconds "$main_cmx")" = "$main_b" ]] || fail "failed publication changed Main's Dune artifact"
[[ "$(mtime_milliseconds "$message_cmx")" = "$message_b" ]] || fail "failed publication changed Message's Dune artifact"
[[ "$(mtime_milliseconds "$executable")" = "$executable_b" ]] || fail "failed publication changed the native executable"

replace_source "version-c" "version-b"
sleep 1
compile
[[ "$(source_bundle_revision)" = "$revision_b" ]] || fail "restored input did not recover the prior source identity"
[[ "$(mtime_milliseconds "$main_cmx")" = "$main_b" ]] || fail "restored input could not reuse Main's prior Dune artifact"
[[ "$(mtime_milliseconds "$message_cmx")" = "$message_b" ]] || fail "restored input could not reuse Message's prior Dune artifact"
[[ "$(mtime_milliseconds "$executable")" = "$executable_b" ]] || fail "restored input could not reuse the prior native executable"

if grep -R -a -F ".reflaxe-output-transaction" "$PROJECT_DIR/out" "$BUILD_DIR" >/dev/null; then
	fail "a private candidate or backup path entered generated output or Dune metadata"
fi
if find "$PROJECT_DIR" -maxdepth 1 -type d -name '.*.reflaxe-output-transaction' -print -quit | grep -q .; then
	fail "private output transaction state survived a completed request"
fi

"$executable" >"$WORK_DIR/runtime.stdout"
grep -Fxq "version-b" "$WORK_DIR/runtime.stdout" || fail "the final native artifact did not run the published program"

echo "REFLAXE_OCAML_TRANSACTIONAL_DUNE:PASS cold_dune_ms=$cold_dune_ms warm_dune_ms=$warm_dune_ms edit_dune_ms=$edit_dune_ms"
