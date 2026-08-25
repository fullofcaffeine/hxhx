#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const interfaceModulePath = 'out/haxe_Constraints.ml'
if (!fs.existsSync(interfaceModulePath))
	throw new Error(`missing generated interface module with exact target filename: ${interfaceModulePath}`)
const interfaceModule = fs.readFileSync(interfaceModulePath, 'utf8')
const generatedMain = fs.readFileSync('out/Main.ml', 'utf8')
const interfaceType = interfaceModule.split('\n').find(line => line.startsWith('type imap_t ='))
const adapter = generatedMain.split('\n').find(line => line.includes('__adapt_standard_imap_'))

if (interfaceType !== 'type imap_t = { __hx_type : Obj.t; get : Obj.t -> Obj.t -> Obj.t; keys : Obj.t -> unit -> Obj.t }')
	throw new Error(`the fixture no longer presents the expected DCE-reduced IMap surface: ${interfaceType}`)
if (!adapter
	|| !adapter.includes('; get =')
	|| !adapter.includes('; keys =')
	|| adapter.includes('; set =')
	|| adapter.includes('let rec __adapt_standard_imap_')) {
	throw new Error('the standard Map adapter did not mirror the retained get/keys interface fields exactly')
}
NODE

echo "IMAP_DCE_RETAINED_ADAPTER_SURFACE:PASS"
