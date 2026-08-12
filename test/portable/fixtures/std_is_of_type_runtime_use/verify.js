#!/usr/bin/env node

const fs = require('node:fs')
const path = require('node:path')

const fixtureRoot = __dirname
const reportPath = path.join(fixtureRoot, 'out', 'ocaml_runtime_requirement_report.json')
const loweringPath = path.join(fixtureRoot, 'out', 'ocaml_lowering_report.json')
const generatedMainPath = path.join(fixtureRoot, 'out', 'Main.ml')

if (!fs.existsSync(reportPath) || !fs.existsSync(loweringPath) || !fs.existsSync(generatedMainPath)) {
	throw new Error('The Std.isOfType fixture must generate its runtime report, lowering report, and Main.ml before verification.')
}

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
const lowering = JSON.parse(fs.readFileSync(loweringPath, 'utf8'))
const owned = report.requirements.filter(requirement =>
	requirement.semanticCapability === 'haxe-std-is-of-type' && requirement.source?.file === 'src/Main.hx')
if (owned.length !== 10) {
	throw new Error(`Expected ten source-owned Std.isOfType runtime requirements, received ${owned.length}.`)
}
for (const requirement of owned) {
	if (!Array.isArray(requirement.rootModules) || requirement.rootModules.length < 1) {
		throw new Error(`Runtime requirement ${requirement.id} has no direct runtime root.`)
	}
}

const decisions = lowering.stdIsOfType.filter(decision => decision.source?.file === 'src/Main.hx')
const expectedStrategies = new Map([
	['static-true', 1],
	['static-false', 1],
	['dynamic-int', 3],
	['dynamic-float', 1],
	['dynamic-bool', 2],
	['runtime-fallback', 4],
])
if (decisions.length !== 12) {
	throw new Error(`Expected twelve source-owned Std.isOfType decisions, received ${decisions.length}.`)
}
for (const [strategy, expectedCount] of expectedStrategies) {
	const actualCount = decisions.filter(decision => decision.strategy === strategy).length
	if (actualCount !== expectedCount) {
		throw new Error(`Expected ${expectedCount} ${strategy} decisions, received ${actualCount}.`)
	}
}

const decisionRequirementIds = decisions.flatMap(decision => decision.runtimeRequirementIds).sort()
const loweringRequirementIds = lowering.runtimeRequirements
	.filter(requirement => requirement.semanticCapability === 'haxe-std-is-of-type' && requirement.source?.file === 'src/Main.hx')
	.map(requirement => requirement.id)
	.sort()
const runtimeRequirementIds = owned.map(requirement => requirement.id).sort()
if (JSON.stringify(decisionRequirementIds) !== JSON.stringify(loweringRequirementIds)
	|| JSON.stringify(decisionRequirementIds) !== JSON.stringify(runtimeRequirementIds)) {
	throw new Error('The sealed type-check decisions and the two runtime reports disagree about source-owned requirements.')
}

const generatedMain = fs.readFileSync(generatedMainPath, 'utf8')
if (!generatedMain.includes('__isOfTypeValue_')) {
	throw new Error('Generated Main.ml does not contain the single-evaluation Std.isOfType binding.')
}

process.stdout.write('STD_IS_OF_TYPE_RUNTIME_USE_REPORT:PASS\n')
