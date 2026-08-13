#!/usr/bin/env bash
set -euo pipefail

SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated standalone-loop source or lowering report" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const targets = report.controlTargets.filter(target =>
	target.functionId.startsWith('standalone:')
	&& target.pipelineRevision === 'ocaml-standalone-expression-plans-v14')
const transfers = report.controls.filter(control =>
	control.functionId.startsWith('standalone:')
	&& control.pipelineRevision === 'ocaml-standalone-expression-plans-v14')

if (targets.length !== 1
	|| transfers.length !== 2
	|| transfers.map(control => control.kind).sort().join(',') !== 'break,continue'
	|| transfers.some(control => control.targetId !== targets[0].id)) {
	throw new Error(`expected one standalone loop target with checked break and continue, got ${targets.length} targets and ${transfers.length} transfers`)
}
if (!source.includes('HxRuntime.Hx_break') || !source.includes('HxRuntime.Hx_continue')) {
	throw new Error('generated standalone initialization omitted its planned loop signals')
}
NODE

echo "REFLAXE_OCAML_STANDALONE_LOOP_CONTROL_FIXTURE:PASS"
