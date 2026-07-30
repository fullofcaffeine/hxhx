#!/usr/bin/env node
/**
 * Small deterministic file helper for the real Reflaxe/Haxe-server matrix.
 *
 * Shell owns compiler and process orchestration. This helper owns structural
 * text replacement, manifest revision reads, and content-only tree digests so
 * the shell test does not accumulate inline source-patching programs.
 */
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

function fail(message) {
	throw new Error(message)
}

function replaceExactly(file, expected, replacement) {
	const source = fs.readFileSync(file, 'utf8')
	const occurrences = source.split(expected).length - 1
	if (occurrences !== 1) {
		fail(`expected exactly one ${JSON.stringify(expected)} in ${file}, found ${occurrences}`)
	}
	fs.writeFileSync(file, source.replace(expected, replacement))
}

function programRevision(manifestPath) {
	const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	if (typeof manifest.programRevision !== 'string' || manifest.programRevision.length === 0) {
		fail(`artifact manifest has no programRevision: ${manifestPath}`)
	}
	process.stdout.write(manifest.programRevision)
}

function sourceBundleRevision(manifestPath) {
	const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	if (typeof manifest?.summary?.sourceBundleRevision !== 'string' || manifest.summary.sourceBundleRevision.length === 0) {
		fail(`artifact manifest has no sourceBundleRevision: ${manifestPath}`)
	}
	process.stdout.write(manifest.summary.sourceBundleRevision)
}

function treeDigest(root) {
	const hash = crypto.createHash('sha256')
	const visit = (directory, prefix) => {
		const entries = fs.readdirSync(directory, {withFileTypes: true})
			.sort((left, right) => left.name < right.name ? -1 : (left.name > right.name ? 1 : 0))
		for (const entry of entries) {
			const relative = prefix === '' ? entry.name : `${prefix}/${entry.name}`
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute, relative)
			} else if (entry.isFile()) {
				hash.update(Buffer.from(relative, 'utf8'))
				hash.update(Buffer.from([0]))
				hash.update(fs.readFileSync(absolute))
				hash.update(Buffer.from([0]))
			} else {
				fail(`unsupported tree entry in digest: ${absolute}`)
			}
		}
	}
	visit(root, '')
	process.stdout.write(`sha256:${hash.digest('hex')}`)
}

function verifyReuseReport(outputDirectory) {
	const reportPath = path.join(outputDirectory, 'ocaml_target_reuse_observation.json')
	const manifestPath = path.join(outputDirectory, 'ocaml_artifact_manifest.json')
	const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
	const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	if (report?.sourceBundleCandidate?.status !== 'packed-observation'
		|| !(report.sourceBundleCandidate.payloadBytes > report.sourceBundleCandidate.packedBytes)
		|| report?.shadowReplay?.status !== 'stable-source-equal'
		|| report.shadowReplay.equal !== true
		|| report.shadowReplay.receiptSemanticsEqual !== true
		|| report.shadowReplay.artifactManifestEqual !== true) {
		fail(`target-reuse shadow proof is incomplete: ${reportPath}`)
	}
	if (manifest?.summary?.completeForSourceBundle !== true
		|| manifest.summary.sourceBundleRevision !== report.sourceBundleCandidate.sourceBundleRevision) {
		fail(`target-reuse report and final source manifest disagree: ${outputDirectory}`)
	}
}

function normalizeReuseSnapshot(outputDirectory) {
	verifyReuseReport(outputDirectory)
	const reportPath = path.join(outputDirectory, 'ocaml_target_reuse_observation.json')
	const manifestPath = path.join(outputDirectory, 'ocaml_artifact_manifest.json')
	const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	const entries = manifest.entries.filter(entry => entry.path !== 'ocaml_target_reuse_observation.json')
	if (entries.length !== manifest.entries.length - 1) {
		fail(`target-reuse report is not owned exactly once: ${manifestPath}`)
	}
	manifest.entries = entries
	manifest.summary.entryCount -= 1
	manifest.summary.volatileEvidenceEntryCount -= 1
	// The artifact-set revision includes the intentionally volatile report.
	// Snapshot comparisons continue to prove the stable source-bundle revision.
	manifest.summary.artifactSetRevision = 'normalized:target-reuse-report-removed'
	fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
	fs.unlinkSync(reportPath)
}

function verifyReusePhasePair(coldPath, warmPath) {
	const cold = JSON.parse(fs.readFileSync(coldPath, 'utf8'))
	const warm = JSON.parse(fs.readFileSync(warmPath, 'utf8'))
	for (const [name, report] of [['cold', cold], ['warm', warm]]) {
		if (report?.model !== 'reflaxe-ocaml-target-reuse-phase' || report?.schemaVersion !== 2) {
			fail(`${name} target-reuse phase report has the wrong model or schema`)
		}
		for (const [phase, value] of Object.entries(report.timing ?? {})) {
			if (!Number.isInteger(value) || value < 0) {
				fail(`${name} target-reuse phase ${phase} is not a non-negative integer`)
			}
		}
		if (!Number.isInteger(report?.macroRealm?.requestSequence)
			|| report.macroRealm.requestSequence < 1
			|| !Number.isInteger(report?.catalog?.payloadBytes)
			|| report.catalog.payloadBytes < 0
			|| !Number.isInteger(report?.catalog?.activeLeases)
			|| report.catalog.activeLeases !== 0) {
			fail(`${name} target-reuse phase report has invalid realm or catalog accounting`)
		}
	}
	if (cold.outcome !== 'compiled-miss'
		|| cold?.work?.semanticCompilerRan !== true
		|| cold.work.missPreparationRan !== true
		|| cold.work.replaySucceeded !== false) {
		fail('cold target-reuse phase did not record one ordinary semantic compilation')
	}
	if (warm.outcome !== 'exact-hit'
		|| warm?.work?.semanticCompilerRan !== false
		|| warm.work.missPreparationRan !== false
		|| warm.work.lookupRan !== true
		|| warm.work.replaySucceeded !== true) {
		fail('warm target-reuse phase did not record one exact replay with no semantic compilation')
	}
	if (cold?.targetRequest?.revision !== warm?.targetRequest?.revision
		|| cold?.finalProgram?.revision !== warm?.finalProgram?.revision
		|| cold?.macroRealm?.identityRevision !== warm?.macroRealm?.identityRevision
		|| warm?.macroRealm?.requestSequence !== cold?.macroRealm?.requestSequence + 1
		|| warm?.macroRealm?.survivedPriorRequest !== true) {
		fail('cold and warm target-reuse phases do not describe one exact request in one persistent macro realm')
	}
	if (!(cold?.work?.payloadBytes > 0)
		|| warm?.work?.payloadBytes !== cold.work.payloadBytes
		|| warm?.catalog?.hits < 1) {
		fail('cold and warm target-reuse phases do not prove admission and a later catalog hit')
	}
}

const [command, ...args] = process.argv.slice(2)
switch (command) {
	case 'replace':
		if (args.length !== 3) fail('replace needs: file expected replacement')
		replaceExactly(args[0], args[1], args[2])
		break
	case 'program-revision':
		if (args.length !== 1) fail('program-revision needs: manifest')
		programRevision(args[0])
		break
	case 'source-bundle-revision':
		if (args.length !== 1) fail('source-bundle-revision needs: manifest')
		sourceBundleRevision(args[0])
		break
	case 'tree-digest':
		if (args.length !== 1) fail('tree-digest needs: directory')
		treeDigest(args[0])
		break
	case 'verify-reuse-report':
		if (args.length !== 1) fail('verify-reuse-report needs: output directory')
		verifyReuseReport(args[0])
		break
	case 'normalize-reuse-snapshot':
		if (args.length !== 1) fail('normalize-reuse-snapshot needs: output directory')
		normalizeReuseSnapshot(args[0])
		break
	case 'verify-reuse-phase-pair':
		if (args.length !== 2) fail('verify-reuse-phase-pair needs: cold-report warm-report')
		verifyReusePhasePair(args[0], args[1])
		break
	default:
		fail(`unknown command: ${command || '<missing>'}`)
}
