#!/usr/bin/env bash
set -euo pipefail

# Upstream Haxe 4.3.7 is the independent behavior oracle. The native OCaml
# program must produce the same text for direct and nullable String aliases.
oracle_output="$(mktemp)"
native_output="$(mktemp)"
trap 'rm -f "$oracle_output" "$native_output"' EXIT
haxe -cp src --main Main --interp >"$oracle_output"
out/_build/default/out.exe >"$native_output"
diff -u "$oracle_output" "$native_output"

# The lowering report must describe the runtime carrier, not the typedef name
# used by the source file. This keeps planner and syntax validation identical.
node - out/ocaml_runtime_requirement_report.json <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decisions = report.requirements.filter(decision =>
	decision.semanticCapability === 'haxe-static-string-conversion'
		&& decision.source.file === 'src/Main.hx'
)
const types = decisions.map(decision => decision.subject.id).sort()
if (types.join(',') !== 'Null<String>,String') {
	throw new Error(`Expected canonical String decisions, received ${types.join(',')}`)
}
NODE
