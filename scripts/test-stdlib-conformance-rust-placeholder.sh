#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT_REPORT="$TMP_DIR/rust-placeholder-report.json"
ALLOWLIST_PATH="docs/00-project/STDLIB_PORTABLE_ALLOWLIST_FAMILY_V1.md"
FIXTURE_ROOT="test/portable/fixtures"

stdout_capture="$TMP_DIR/stdout.txt"

node scripts/stdlib/run-conformance-adapter-rust-placeholder.js \
	--target-id rust \
	--tier tier1 \
	--allowlist-path "$ALLOWLIST_PATH" \
	--fixture-root "$FIXTURE_ROOT" \
	--report-path "$OUT_REPORT" \
	--strict-native-surface true \
	--corpus-manifest-path test/portable/semantic_diff/corpus_v1.json \
	--slice-id core_seed_v1 >"$stdout_capture"

if ! grep -q "PORTABLE_CONFORMANCE_RUNNER_START target=rust tier=tier1" "$stdout_capture"; then
	echo "missing runner start marker" >&2
	exit 1
fi

if ! grep -q "PORTABLE_CONFORMANCE_RUNNER_SKIP target=rust tier=tier1 reason=placeholder_not_implemented_in_this_repo" "$stdout_capture"; then
	echo "missing runner skip marker" >&2
	exit 1
fi

node - <<'NODE' "$OUT_REPORT" "$ALLOWLIST_PATH" "$FIXTURE_ROOT"
const fs = require('fs')

const reportPath = process.argv[2]
const allowlistPath = process.argv[3]
const fixtureRoot = process.argv[4]

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))

function assertEqual(actual, expected, label) {
	if (actual !== expected) {
		throw new Error(`${label}: expected ${expected}, got ${actual}`)
	}
}

assertEqual(report.schemaVersion, 1, 'schemaVersion')
assertEqual(report.contractId, 'reflaxe.family.std.portable_conformance_runner', 'contractId')
assertEqual(report.contractVersion, '1.0.0', 'contractVersion')
assertEqual(report.targetId, 'rust', 'targetId')
assertEqual(report.tier, 'tier1', 'tier')
assertEqual(report.strictNativeSurface, true, 'strictNativeSurface')
assertEqual(report.status, 'skip', 'status')
assertEqual(report.summary.total, 0, 'summary.total')
assertEqual(report.summary.passed, 0, 'summary.passed')
assertEqual(report.summary.failed, 0, 'summary.failed')
assertEqual(report.summary.skipped, 0, 'summary.skipped')
assertEqual(Array.isArray(report.fixtures), true, 'fixtures array')
assertEqual(report.fixtures.length, 0, 'fixtures length')
assertEqual(report.adapter.mode, 'placeholder', 'adapter.mode')
assertEqual(report.adapter.reason, 'placeholder_not_implemented_in_this_repo', 'adapter.reason')
assertEqual(report.inputs.allowlistPath, allowlistPath, 'inputs.allowlistPath')
assertEqual(report.inputs.fixtureRoot, fixtureRoot, 'inputs.fixtureRoot')
NODE

echo "✓ rust conformance placeholder adapter OK"
