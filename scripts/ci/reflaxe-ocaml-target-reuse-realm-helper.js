#!/usr/bin/env node
'use strict'

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[reflaxe-ocaml-target-reuse-realm] ERROR: ${message}`)
	process.exit(1)
}

function load(directory, label) {
	const reportPath = path.join(directory, `${label}.json`)
	if (!fs.existsSync(reportPath)) fail(`missing report snapshot ${label}`)
	const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
	if (report?.model !== 'reflaxe-ocaml-target-reuse-phase' || report?.schemaVersion !== 2) {
		fail(`${label} uses an unsupported phase-receipt schema`)
	}
	const realm = report.macroRealm
	const catalog = report.catalog
	const target = report.targetRequest
	if (!/^sha256:[0-9a-f]{64}$/.test(String(realm?.identityRevision || ''))) {
		fail(`${label} does not identify the macro realm that owned the request`)
	}
	if (!Number.isInteger(realm.requestSequence) || realm.requestSequence < 1) {
		fail(`${label} has an invalid realm request sequence`)
	}
	if (catalog?.totalBudgetBytes !== 128 * 1024 * 1024
		|| catalog.maximumEntryBytes !== 64 * 1024 * 1024
		|| catalog.entryCount !== 0
		|| catalog.payloadBytes !== 0
		|| catalog.activeLeases !== 0) {
		fail(`${label} does not report the empty bounded catalog expected while reuse is disabled`)
	}
	if (!/^sha256:[0-9a-f]{64}$/.test(String(target?.revision || ''))
		|| target.eligible !== false
		|| !Array.isArray(target.blockers)
		|| target.blockers.length === 0) {
		fail(`${label} does not contain one fail-closed exact target request`)
	}
	if (report.outcome !== 'compiled-miss'
		|| report?.work?.semanticCompilerRan !== true
		|| report.work.missPreparationRan !== true
		|| report.work.replaySucceeded !== false) {
		fail(`${label} did not record the ordinary target compiler required while reuse is disabled`)
	}
	return report
}

function sameRealmProgress(left, right, label) {
	if (left.macroRealm.identityRevision !== right.macroRealm.identityRevision) fail(`${label} unexpectedly replaced the macro realm`)
	if (right.macroRealm.requestSequence <= left.macroRealm.requestSequence || right.macroRealm.survivedPriorRequest !== true) {
		fail(`${label} did not advance within the surviving macro realm`)
	}
}

function main() {
	const directory = process.argv[2]
	if (!directory) fail('usage: reflaxe-ocaml-target-reuse-realm-helper.js <snapshot-directory>')
	const cold = load(directory, 'cold')
	const repeat = load(directory, 'repeat')
	const explicitReset = load(directory, 'explicit-reset')
	const macroChange = load(directory, 'macro-change')
	const afterMacroError = load(directory, 'after-macro-error')
	const noMacroCache = load(directory, 'no-macro-cache')
	const afterNoMacroCache = load(directory, 'after-no-macro-cache')
	const signatureChange = load(directory, 'signature-change')
	const signatureRestored = load(directory, 'signature-restored')
	const restart = load(directory, 'restart')

	sameRealmProgress(cold, repeat, 'exact repeat')
	if (repeat.targetRequest.revision !== cold.targetRequest.revision) fail('exact repeat changed the target request revision')

	sameRealmProgress(repeat, explicitReset, 'explicit reset')
	if (explicitReset.macroRealm.resetGeneration !== repeat.macroRealm.resetGeneration + 1
		|| explicitReset.macroRealm.resetCause !== 'fixture-explicit-reset') {
		fail('explicit reset did not advance and explain the reset generation')
	}
	if (explicitReset.targetRequest.revision !== repeat.targetRequest.revision) fail('explicit reset changed the semantic target request')

	if (macroChange.targetRequest.revision === explicitReset.targetRequest.revision) {
		fail('changed build-macro output did not invalidate the target request')
	}
	const macroChangeRealm = macroChange.macroRealm.identityRevision === explicitReset.macroRealm.identityRevision ? 'survived' : 'replaced'

	if (afterMacroError.targetRequest.revision !== macroChange.targetRequest.revision) {
		fail('post-error success did not restore the same target request')
	}
	const macroErrorRealm = afterMacroError.macroRealm.identityRevision === macroChange.macroRealm.identityRevision ? 'survived' : 'replaced'
	if (macroErrorRealm === 'survived') {
		sameRealmProgress(macroChange, afterMacroError, 'post-error success')
	} else if (afterMacroError.macroRealm.requestSequence !== 1 || afterMacroError.macroRealm.survivedPriorRequest !== false) {
		fail('post-error success reported an inconsistent replacement macro realm')
	}

	if (!noMacroCache.targetRequest.blockers.includes('reflaxe:no-macro-cache')) {
		fail('NoMacroCache request omitted its fail-closed framework blocker')
	}
	if (noMacroCache.macroRealm.requestSequence !== 1 || noMacroCache.macroRealm.survivedPriorRequest !== false) {
		fail('NoMacroCache request did not use a cold macro realm')
	}
	if (afterNoMacroCache.targetRequest.blockers.includes('reflaxe:no-macro-cache')) {
		fail('ordinary request retained the NoMacroCache blocker')
	}
	if (afterNoMacroCache.macroRealm.identityRevision === noMacroCache.macroRealm.identityRevision) {
		fail('ordinary request reused the short-lived NoMacroCache realm')
	}
	if (afterNoMacroCache.targetRequest.revision !== afterMacroError.targetRequest.revision) {
		fail('NoMacroCache transition changed the ordinary semantic target request')
	}

	if (signatureChange.targetRequest.revision === afterNoMacroCache.targetRequest.revision) {
		fail('classpath/signature change did not invalidate the target request')
	}
	if (signatureRestored.targetRequest.revision !== afterNoMacroCache.targetRequest.revision) {
		fail('restoring the classpath/signature did not restore the exact request revision')
	}
	const signatureRealm = signatureChange.macroRealm.identityRevision === afterNoMacroCache.macroRealm.identityRevision ? 'survived' : 'replaced'

	if (restart.targetRequest.revision !== signatureRestored.targetRequest.revision) {
		fail('server restart changed the semantic target request')
	}
	if (restart.macroRealm.identityRevision === signatureRestored.macroRealm.identityRevision
		|| restart.macroRealm.requestSequence !== 1
		|| restart.macroRealm.survivedPriorRequest !== false) {
		fail('server restart did not create a fresh macro realm')
	}

	console.log(
		`REFLAXE_OCAML_TARGET_REUSE_REALM:PASS macro_change_realm=${macroChangeRealm} macro_error_realm=${macroErrorRealm} signature_change_realm=${signatureRealm}`
	)
}

main()
