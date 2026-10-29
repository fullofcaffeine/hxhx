#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd ../../../.. && pwd)"
"${HAXE_BIN:-haxe}" -cp "$repo_root/packages/reflaxe.ocaml/src" -cp . --run VerifyContract
node <<'NODE'
const fs = require('fs');
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'));
const aliases = report.iMapStorageAliases.filter(x => x.functionId.includes('|Catalog|instance|function|check|'));
const sources = new Set(aliases.map(x => x.sourceSemanticTypeId));
if (aliases.length !== 3 || !sources.has('Map<String, Item>') || !sources.has('haxe.ds.Map<String, Item>'))
  throw new Error('The report must retain all three aliases and both exact source type forms');
NODE
