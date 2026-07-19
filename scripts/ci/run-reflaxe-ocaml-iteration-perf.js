#!/usr/bin/env node
/** Runs only the report-only standalone edit-loop workload for focused iteration. */
const fs = require('fs')
const path = require('path')

const { measureIterationScenario } = require('./reflaxe-ocaml-iteration-perf')
const {
	cleanupPerformanceContext,
	createPerformanceContext,
	environmentSummary,
	provenanceSummary,
	verifyEvidenceSanitized
} = require('./reflaxe-ocaml-perf-platform')
const { stats } = require('./run-reflaxe-ocaml-perf')

const repoRoot = process.cwd()
const baselinePath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json')
const artifactsDirectory = path.resolve(process.env.RO_ITERATION_ARTIFACTS || path.join(repoRoot, '.artifacts/reflaxe-ocaml/iteration-perf'))

function main() {
	const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'))
	const context = createPerformanceContext({
		repoRoot,
		artifactsDir: artifactsDirectory,
		mode: 'reference-gate'
	})
	fs.rmSync(context.artifactsDir, { recursive: true, force: true })
	fs.mkdirSync(context.artifactsDir, { recursive: true })
	try {
		const summary = {
			schemaVersion: 1,
			marker: 'RO_TARGET_ITERATION_REPORT:FAIL',
			generatedAt: new Date().toISOString(),
			method: {
				id: 'standalone-reflaxe-iteration-v1',
				durationUnit: 'milliseconds',
				rawSamplesRetained: true,
				sampleOrderPreserved: true,
				thresholdMode: 'report-only-until-stable-hosted-trend',
				crossHostAbsoluteComparisonAllowed: false
			},
			environment: environmentSummary(context),
			provenance: provenanceSummary(context),
			evidence: { machineLocalPathsRedacted: true },
			iteration: measureIterationScenario(baseline.iterationScenario, context, stats, context.artifactsDir)
		}
		summary.marker = 'RO_TARGET_ITERATION_REPORT:PASS'
		fs.writeFileSync(path.join(context.artifactsDir, 'summary.json'), JSON.stringify(summary, null, 2) + '\n')
		verifyEvidenceSanitized(context)
		console.log(`[reflaxe-ocaml-iteration] summary=${path.relative(repoRoot, path.join(context.artifactsDir, 'summary.json'))}`)
		console.log(summary.marker)
		return true
	} finally {
		cleanupPerformanceContext(context)
	}
}

if (require.main === module) {
	try {
		process.exitCode = main() ? 0 : 1
	} catch (error) {
		console.error(`[reflaxe-ocaml-iteration] ERROR: ${error instanceof Error ? error.message : String(error)}`)
		process.exitCode = 1
	}
}

module.exports = { main }
