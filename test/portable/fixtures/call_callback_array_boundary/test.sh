#!/usr/bin/env bash
set -euo pipefail

# The portable runner has compiled and executed the native artifact. Compare
# the same authored source with upstream Haxe as a second behavior observer.
upstream_stdout="$(mktemp)"
trap 'rm -f "$upstream_stdout"' EXIT
haxe -cp ../../../oracle/reflaxe_ocaml_callback_array_boundary_seed/src -main Main --interp > "$upstream_stdout"
diff -u expected.stdout "$upstream_stdout"

node - out/ocaml_lowering_report.json <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
// Array storage has its own existing representation. Recognizing that generic
// shape must not publish a callback identity layout that cannot carry it.
const promoted = report.callableBoundaries.filter(declaration =>
	declaration.sourceModuleId === 'Main' && declaration.sourceFieldName === 'apply'
	&& declaration.proofId === 'direct-static-callable-view-signature-v1')
if (promoted.length !== 0) {
	throw new Error('the array-taking method acquired an unsupported callback identity layout')
}
NODE

echo "CALLBACK_ARRAY_BOUNDARY:PASS"
