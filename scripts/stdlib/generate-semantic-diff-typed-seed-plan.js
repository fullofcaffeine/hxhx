#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[semantic-diff] ERROR: ${message}`)
	process.exit(1)
}

function parsePositiveInt(rawValue, label) {
	if (rawValue == null || rawValue.length === 0) {
		fail(`missing value for ${label}`)
	}
	const parsedValue = Number.parseInt(rawValue, 10)
	if (!Number.isFinite(parsedValue) || Number.isNaN(parsedValue) || parsedValue < 1) {
		fail(`${label} must be a positive integer (received: ${rawValue})`)
	}
	return parsedValue
}

function parseSeed(rawValue) {
	if (rawValue == null || rawValue.length === 0) {
		fail('missing value for --seed')
	}
	const parsedValue = Number.parseInt(rawValue, 10)
	if (!Number.isFinite(parsedValue) || Number.isNaN(parsedValue)) {
		fail(`--seed must be an integer (received: ${rawValue})`)
	}
	return parsedValue >>> 0
}

function parseArgs(argv) {
	const options = {
		manifestPath: 'test/portable/semantic_diff/corpus_v1.json',
		sliceId: 'core_seed_v1',
		seed: 1,
		count: 32,
		outPath: null,
		replayConfigPath: null,
		printJson: true,
	}

	for (let index = 2; index < argv.length; index += 1) {
		const arg = argv[index]
		if (arg === '--manifest') {
			options.manifestPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--slice') {
			options.sliceId = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--seed') {
			options.seed = parseSeed(argv[index + 1])
			index += 1
			continue
		}
		if (arg === '--count') {
			options.count = parsePositiveInt(argv[index + 1], '--count')
			index += 1
			continue
		}
		if (arg === '--out') {
			options.outPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--replay-config') {
			options.replayConfigPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--no-print-json') {
			options.printJson = false
			continue
		}
		fail(`unknown argument: ${arg}`)
	}

	return options
}

function readJsonFile(filePath) {
	try {
		return JSON.parse(fs.readFileSync(filePath, 'utf8'))
	} catch (error) {
		fail(`invalid json at ${filePath}: ${error}`)
	}
}

function createXorShift32(seed) {
	let state = seed >>> 0
	if (state === 0) {
		state = 0x9e3779b9
	}
	return {
		nextUInt() {
			state ^= state << 13
			state ^= state >>> 17
			state ^= state << 5
			return state >>> 0
		},
		nextIndex(limit) {
			if (limit <= 0) {
				return 0
			}
			return this.nextUInt() % limit
		},
	}
}

function deterministicRelativePath(repoRoot, inputPath) {
	const absoluteInputPath = path.resolve(repoRoot, inputPath)
	return path.relative(repoRoot, absoluteInputPath).split(path.sep).join('/')
}

const PORTABLE_GRAMMAR_CONSTRAINTS = {
	allowedConstructs: [
		'literals_arithmetic_boolean',
		'if_else_switch_loops',
		'function_calls',
		'array_map_stringbuf_bytes',
		'typed_try_catch_throw',
	],
	forbiddenConstructs: [
		'target_native_packages',
		'macro_eval_apis',
		'filesystem_network_side_effects',
		'host_clock_or_unseeded_randomness',
	],
}

const MUTATION_TEMPLATES = [
	{
		id: 'numeric_literal_delta',
		category: 'expressions',
		requiredConstraints: ['literals_arithmetic_boolean'],
		parameterKinds: ['delta'],
	},
	{
		id: 'boolean_literal_flip',
		category: 'expressions',
		requiredConstraints: ['literals_arithmetic_boolean'],
		parameterKinds: ['toggle'],
	},
	{
		id: 'string_literal_suffix',
		category: 'expressions',
		requiredConstraints: ['function_calls'],
		parameterKinds: ['suffix'],
	},
	{
		id: 'array_append_same_type',
		category: 'collections',
		requiredConstraints: ['array_map_stringbuf_bytes'],
		parameterKinds: ['appendValueClass'],
	},
	{
		id: 'switch_case_literal_permutation',
		category: 'control_flow',
		requiredConstraints: ['if_else_switch_loops'],
		parameterKinds: ['permuteWindow'],
	},
	{
		id: 'typed_catch_message_literal',
		category: 'exceptions',
		requiredConstraints: ['typed_try_catch_throw'],
		parameterKinds: ['messageToken'],
	},
]

function buildTemplateParam(templateId, generator) {
	if (templateId === 'numeric_literal_delta') {
		const deltas = [-3, -2, -1, 1, 2, 3]
		return { delta: deltas[generator.nextIndex(deltas.length)] }
	}
	if (templateId === 'boolean_literal_flip') {
		return { toggle: true }
	}
	if (templateId === 'string_literal_suffix') {
		const suffixes = ['_A', '_B', '_C', '_N']
		return { suffix: suffixes[generator.nextIndex(suffixes.length)] }
	}
	if (templateId === 'array_append_same_type') {
		const classes = ['int_literal', 'float_literal', 'string_literal', 'bool_literal']
		return { appendValueClass: classes[generator.nextIndex(classes.length)] }
	}
	if (templateId === 'switch_case_literal_permutation') {
		const windows = [2, 3, 4]
		return { permuteWindow: windows[generator.nextIndex(windows.length)] }
	}
	if (templateId === 'typed_catch_message_literal') {
		const tokens = ['E_A', 'E_B', 'E_C', 'E_D']
		return { messageToken: tokens[generator.nextIndex(tokens.length)] }
	}
	fail(`missing parameter builder for template: ${templateId}`)
}

function selectSliceFixtures(corpusManifest, sliceId) {
	if (!Array.isArray(corpusManifest.slices)) {
		fail('corpus manifest must contain slices array')
	}
	const slice = corpusManifest.slices.find((value) => value.id === sliceId)
	if (slice == null) {
		fail(`missing corpus slice: ${sliceId}`)
	}
	if (!Array.isArray(slice.fixtures) || slice.fixtures.length === 0) {
		fail(`corpus slice has no fixtures: ${sliceId}`)
	}

	const normalizedFixtures = []
	for (const fixtureValue of slice.fixtures) {
		if (typeof fixtureValue !== 'string' || fixtureValue.trim().length === 0) {
			fail(`slice ${sliceId} contains invalid fixture id: ${fixtureValue}`)
		}
		normalizedFixtures.push(fixtureValue.trim())
	}
	return normalizedFixtures
}

function assertTemplateConstraints() {
	const allowedConstructSet = new Set(PORTABLE_GRAMMAR_CONSTRAINTS.allowedConstructs)
	for (const template of MUTATION_TEMPLATES) {
		for (const constraint of template.requiredConstraints) {
			if (!allowedConstructSet.has(constraint)) {
				fail(`template ${template.id} requires unknown constraint: ${constraint}`)
			}
		}
	}
}

function generateMutationPlan({
	repoRoot,
	manifestPath,
	sliceId,
	seed,
	count,
}) {
	assertTemplateConstraints()
	const corpusManifest = readJsonFile(manifestPath)
	const fixtures = selectSliceFixtures(corpusManifest, sliceId)
	const generator = createXorShift32(seed)
	const mutations = []

	for (let index = 0; index < count; index += 1) {
		const fixtureId = fixtures[generator.nextIndex(fixtures.length)]
		const template = MUTATION_TEMPLATES[generator.nextIndex(MUTATION_TEMPLATES.length)]
		const parameters = buildTemplateParam(template.id, generator)

		mutations.push({
			sequenceIndex: index,
			fixtureId,
			templateId: template.id,
			templateCategory: template.category,
			requiredConstraints: template.requiredConstraints,
			parameters,
		})
	}

	const manifestRef = deterministicRelativePath(repoRoot, manifestPath)
	return {
		schemaVersion: 1,
		contractId: 'reflaxe.family.std.typed_mutation_seed_plan',
		contractVersion: '1.0.0',
		generatorVersion: 'v1',
		seed,
		sliceId,
		count,
		manifestRef,
		portableGrammarConstraints: PORTABLE_GRAMMAR_CONSTRAINTS,
		templateCatalog: MUTATION_TEMPLATES,
		fixtures,
		mutations,
		replay: {
			command: `node scripts/stdlib/generate-semantic-diff-typed-seed-plan.js --replay-config ${manifestRef}`,
		},
	}
}

function writeJsonFile(filePath, payload) {
	const absolutePath = path.resolve(filePath)
	fs.mkdirSync(path.dirname(absolutePath), { recursive: true })
	fs.writeFileSync(absolutePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8')
}

function normalizeReplayInput(repoRoot, replayPayload, replayPath) {
	if (replayPayload == null || typeof replayPayload !== 'object') {
		fail(`invalid replay payload in ${replayPath}`)
	}
	const manifestRef = replayPayload.manifestRef
	if (typeof manifestRef !== 'string' || manifestRef.length === 0) {
		fail(`replay payload must include manifestRef: ${replayPath}`)
	}
	return {
		repoRoot,
		manifestPath: path.resolve(repoRoot, manifestRef),
		sliceId: replayPayload.sliceId,
		seed: replayPayload.seed,
		count: replayPayload.count,
	}
}

function verifyReplay(repoRoot, replayConfigPath) {
	const replayPayload = readJsonFile(replayConfigPath)
	const input = normalizeReplayInput(repoRoot, replayPayload, replayConfigPath)
	const regenerated = generateMutationPlan(input)
	const replayString = JSON.stringify(replayPayload)
	const regeneratedString = JSON.stringify(regenerated)
	if (replayString !== regeneratedString) {
		fail(`replay mismatch for ${replayConfigPath}`)
	}
	console.log(
		`[semantic-diff] REPLAY_OK seed=${replayPayload.seed} slice=${replayPayload.sliceId} count=${replayPayload.count}`
	)
}

function main() {
	const repoRoot = path.resolve(__dirname, '..', '..')
	const options = parseArgs(process.argv)

	if (options.replayConfigPath != null) {
		verifyReplay(repoRoot, path.resolve(repoRoot, options.replayConfigPath))
		return
	}

	const manifestPath = path.resolve(repoRoot, options.manifestPath)
	const plan = generateMutationPlan({
		repoRoot,
		manifestPath,
		sliceId: options.sliceId,
		seed: options.seed,
		count: options.count,
	})

	if (options.outPath != null) {
		writeJsonFile(path.resolve(repoRoot, options.outPath), plan)
		console.log(`[semantic-diff] WROTE_PLAN path=${options.outPath} seed=${plan.seed} count=${plan.count}`)
	}
	if (options.printJson) {
		process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`)
	}
}

main()
