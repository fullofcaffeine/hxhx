#!/usr/bin/env node

/**
 * Freezes source locations that can still create private `Hx...` references.
 *
 * This is a migration guard, not a correctness proof. It finds direct target
 * identifier constructors, known generated-text builders, and raw OCaml
 * constructors in the Haxe-authored target. Later work will replace these
 * legacy entries with checked per-use references. Until then, CI prevents the
 * unexplained surface from growing unnoticed.
 */

const crypto = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')
const {spawnSync} = require('node:child_process')

const REPO_ROOT = path.resolve(__dirname, '..', '..')
const SOURCE_ROOT = 'packages/reflaxe.ocaml/src/reflaxe/ocaml'
const INVENTORY_PATH = 'docs/00-project/REFLAXE_OCAML_PRIVATE_RUNTIME_REFERENCE_INVENTORY.json'
const SCHEMA = 'reflaxe-ocaml-private-runtime-reference-inventory.v1'
const MODEL = 'source-level-legacy-reference-migration-inventory'
const PRIVATE_REFERENCE = /\b(Hx[A-Z][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)/g

const quotedString = String.raw`(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')`
const structuredConstructors = [
	{
		domain: 'expression',
		construction: 'EField(EIdent)',
		pattern: new RegExp(String.raw`\b(?:OcamlExpr\.)?EField\s*\(\s*(?:OcamlExpr\.)?EIdent\s*\(\s*${quotedString}\s*\)\s*,\s*${quotedString}`, 'g'),
		values: match => [`${match[1] || match[2]}.${match[3] || match[4]}`],
	},
	{
		domain: 'expression', construction: 'EIdent',
		pattern: new RegExp(String.raw`\b(?:OcamlExpr\.)?EIdent\s*\(\s*${quotedString}`, 'g'),
		values: match => [match[1] || match[2]],
	},
	{
		domain: 'type', construction: 'TIdent',
		pattern: new RegExp(String.raw`\b(?:OcamlTypeExpr\.)?TIdent\s*\(\s*${quotedString}`, 'g'),
		values: match => [match[1] || match[2]],
	},
	{
		domain: 'type', construction: 'TApp',
		pattern: new RegExp(String.raw`\b(?:OcamlTypeExpr\.)?TApp\s*\(\s*${quotedString}`, 'g'),
		values: match => [match[1] || match[2]],
	},
	{
		domain: 'pattern', construction: 'PConstructor',
		pattern: new RegExp(String.raw`\b(?:OcamlPat\.)?PConstructor\s*\(\s*${quotedString}`, 'g'),
		values: match => [match[1] || match[2]],
	},
]

function normalized(relativePath) {
	return relativePath.split(path.sep).join('/')
}

function lineNumberAt(source, offset) {
	let line = 1
	for (let index = 0; index < offset; index += 1) {
		if (source.charCodeAt(index) === 10) line += 1
	}
	return line
}

/** Removes comments while preserving strings, offsets, and line numbers. */
function maskHaxeComments(source) {
	const chars = source.split('')
	let blockDepth = 0
	let lineComment = false
	let inString = false
	let quote = ''
	let escaped = false
	for (let index = 0; index < chars.length; index += 1) {
		const current = chars[index]
		const next = chars[index + 1]
		if (lineComment) {
			if (current === '\n') lineComment = false
			else chars[index] = ' '
			continue
		}
		if (blockDepth > 0) {
			if (current === '/' && next === '*') {
				chars[index] = ' '
				chars[index + 1] = ' '
				blockDepth += 1
				index += 1
			} else if (current === '*' && next === '/') {
				chars[index] = ' '
				chars[index + 1] = ' '
				blockDepth -= 1
				index += 1
			} else if (current !== '\n') {
				chars[index] = ' '
			}
			continue
		}
		if (inString) {
			if (escaped) escaped = false
			else if (current === '\\') escaped = true
			else if (current === quote) inString = false
			continue
		}
		if (current === '"' || current === "'") {
			inString = true
			quote = current
		} else if (current === '/' && next === '/') {
			chars[index] = ' '
			chars[index + 1] = ' '
			lineComment = true
			index += 1
		} else if (current === '/' && next === '*') {
			chars[index] = ' '
			chars[index + 1] = ' '
			blockDepth = 1
			index += 1
		}
	}
	return chars.join('')
}

function privateReferences(text) {
	const references = []
	for (const match of text.matchAll(PRIVATE_REFERENCE)) references.push(match[1])
	return [...new Set(references)].sort()
}

function rootModule(symbol) {
	const dot = symbol.indexOf('.')
	return dot === -1 ? symbol : symbol.slice(0, dot)
}

function builderFamily(domain, symbol) {
	if (domain === 'raw-boundary') return 'builder-raw-boundary'
	if (symbol == null) return 'builder-unclassified'
	const root = rootModule(symbol)
	if (root === 'HxRuntime') {
		if (/\.Hx_(?:break|continue|return|return_void)$/.test(symbol)) return 'builder-control-transfer'
		if (/exception|throw/.test(symbol)) return 'builder-exceptions'
		if (/\.hx_null$|\.is_null$|\.nullable_/.test(symbol)) return 'builder-nullable-carriers'
		if (/box_bool|is_boxed_bool|unbox_bool/.test(symbol)) return 'builder-boolean-carriers'
		if (/\.tags_has$/.test(symbol)) return 'builder-runtime-tags'
		return 'builder-dynamic-runtime'
	}
	const moduleFamily = root.replace(/^Hx/, '').replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()
	return `builder-${moduleFamily}`
}

function familyFor(relativePath, domain, symbol) {
	const baseName = path.basename(relativePath, '.hx')
	if (baseName === 'OcamlBuilder') return builderFamily(domain, symbol)
	if (baseName === 'OcamlCompiler') return domain === 'generated-text' ? 'compiler-generated-modules' : 'compiler-core'
	if (baseName === 'DuneProjectEmitter') return 'plugin-build-generated-text'
	if (baseName === 'OcamlPlaceAssignmentEmitter') return 'place-assignment'
	return baseName
		.replace(/^Ocaml/, '')
		.replace(/([a-z0-9])([A-Z])/g, '$1-$2')
		.toLowerCase()
}

function addRecord(records, record, source, offset) {
	records.push({
		...record,
		rootModule: record.symbol == null ? null : rootModule(record.symbol),
		migrationFamily: familyFor(record.path, record.domain, record.symbol),
		line: lineNumberAt(source, offset),
		offset,
	})
}

function findClosingParenthesis(source, openIndex) {
	let depth = 0
	let inString = false
	let quote = ''
	let escaped = false
	for (let index = openIndex; index < source.length; index += 1) {
		const current = source[index]
		if (inString) {
			if (escaped) escaped = false
			else if (current === '\\') escaped = true
			else if (current === quote) inString = false
			continue
		}
		if (current === '"' || current === "'") {
			inString = true
			quote = current
		} else if (current === '(') {
			depth += 1
		} else if (current === ')') {
			depth -= 1
			if (depth === 0) return index
		}
	}
	return -1
}

function stringContents(source) {
	const values = []
	const pattern = new RegExp(quotedString, 'g')
	for (const match of source.matchAll(pattern)) values.push(match[1] || match[2])
	return values
}

function discoverStructured(records, relativePath, source, masked) {
	const fieldIdentifierRanges = []
	for (const definition of structuredConstructors) {
		definition.pattern.lastIndex = 0
		for (const match of masked.matchAll(definition.pattern)) {
			if (definition.construction === 'EIdent'
				&& fieldIdentifierRanges.some(range => match.index >= range.start && match.index < range.end)) continue

			const symbols = privateReferences(definition.values(match).join('\n'))
			if (symbols.length === 0) continue
			if (definition.construction === 'EField(EIdent)') {
				fieldIdentifierRanges.push({start: match.index, end: match.index + match[0].length})
			}
			for (const symbol of symbols) {
				addRecord(records, {
					path: relativePath,
					domain: definition.domain,
					construction: definition.construction,
					symbol,
				}, source, match.index)
			}
		}
	}
}

function discoverGeneratedText(records, relativePath, source, masked) {
	const sink = /\b(?:lines|out|rendered|buffer)\.(?:push|add)\s*\(/g
	for (const match of masked.matchAll(sink)) {
		const openIndex = match.index + match[0].lastIndexOf('(')
		const closeIndex = findClosingParenthesis(masked, openIndex)
		if (closeIndex === -1) continue
		const callSource = masked.slice(openIndex + 1, closeIndex)
		const symbols = privateReferences(stringContents(callSource).join('\n'))
		for (const symbol of symbols) {
			addRecord(records, {
				path: relativePath,
				domain: 'generated-text',
				construction: match[0].slice(0, -1).trim(),
				symbol,
			}, source, match.index)
		}
	}
}

/** Finds explicit temporary placeholders without counting checked runtime uses as legacy. */
function discoverLegacyGeneratedText(records, relativePath, source, masked) {
	const legacyCall = /\b(addLegacyRuntimeUse|legacyRuntimeToken)\s*\(/g
	for (const match of masked.matchAll(legacyCall)) {
		const openIndex = match.index + match[0].lastIndexOf('(')
		const closeIndex = findClosingParenthesis(masked, openIndex)
		if (closeIndex === -1) continue
		const callSource = masked.slice(openIndex + 1, closeIndex)
		for (const symbol of privateReferences(stringContents(callSource).join('\n'))) {
			addRecord(records, {
				path: relativePath,
				domain: 'generated-text',
				construction: match[1],
				symbol,
			}, source, match.index)
		}
	}
}

function discoverRawBoundaries(records, relativePath, source, masked) {
	const rawConstructor = /\b(?:OcamlExpr\.)?ERaw\s*\(/g
	for (const match of masked.matchAll(rawConstructor)) {
		const lineStart = masked.lastIndexOf('\n', match.index) + 1
		const linePrefix = masked.slice(lineStart, match.index)
		if (/\bcase\b/.test(linePrefix)) continue
		if (relativePath.endsWith('/OcamlExpr.hx') && linePrefix.trim() === '') continue
		addRecord(records, {
			path: relativePath,
			domain: 'raw-boundary',
			construction: match[0].startsWith('OcamlExpr.') ? 'OcamlExpr.ERaw' : 'ERaw',
			symbol: null,
		}, source, match.index)
	}
}

/** Finds the legacy construction surface in already-loaded Haxe sources. */
function discoverFromSourceMap(sourceMap) {
	const records = []
	for (const [relativePath, source] of [...sourceMap.entries()].sort(([left], [right]) => left.localeCompare(right))) {
		const masked = maskHaxeComments(source)
		discoverStructured(records, relativePath, source, masked)
		discoverGeneratedText(records, relativePath, source, masked)
		discoverLegacyGeneratedText(records, relativePath, source, masked)
		discoverRawBoundaries(records, relativePath, source, masked)
	}

	records.sort((left, right) =>
		left.path.localeCompare(right.path)
		|| left.offset - right.offset
		|| left.domain.localeCompare(right.domain)
		|| left.construction.localeCompare(right.construction)
		|| String(left.symbol).localeCompare(String(right.symbol)))
	const ordinals = new Map()
	return records.map(record => {
		const ordinalKey = [record.path, record.domain, record.construction, record.symbol].join('\u0000')
		const ordinal = (ordinals.get(ordinalKey) || 0) + 1
		ordinals.set(ordinalKey, ordinal)
		return {...record, ordinal}
	})
}

function listHaxeSources(repoRoot = REPO_ROOT) {
	const result = spawnSync('git', ['ls-files', '--', `${SOURCE_ROOT}/**/*.hx`, `${SOURCE_ROOT}/*.hx`], {
		cwd: repoRoot,
		encoding: 'utf8',
	})
	if (result.status !== 0) throw new Error(`git ls-files failed: ${(result.stderr || result.stdout).trim()}`)
	return result.stdout.split(/\r?\n/).filter(Boolean).sort()
}

function loadRepositorySourceMap(repoRoot = REPO_ROOT) {
	return new Map(listHaxeSources(repoRoot).map(relativePath => [
		normalized(relativePath),
		fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'),
	]))
}

function stableEntry(record) {
	return {
		id: [record.path, record.domain, record.construction, record.symbol || 'opaque', record.ordinal].join('::'),
		path: record.path,
		domain: record.domain,
		construction: record.construction,
		symbol: record.symbol,
		rootModule: record.rootModule,
		ordinal: record.ordinal,
		migrationFamily: record.migrationFamily,
	}
}

function countBy(entries, field) {
	const counts = {}
	for (const entry of entries) counts[entry[field]] = (counts[entry[field]] || 0) + 1
	return Object.fromEntries(Object.entries(counts).sort(([left], [right]) => left.localeCompare(right)))
}

function inventoryRevision(entries) {
	return crypto.createHash('sha256').update(JSON.stringify(entries)).digest('hex')
}

/** Builds the committed, line-number-independent migration snapshot. */
function buildInventory(records, reviewBead) {
	const entries = records.map(stableEntry)
	return {
		schema: SCHEMA,
		model: MODEL,
		authority: 'migration-inventory-only',
		reviewBead,
		sourceRoot: SOURCE_ROOT,
		generator: 'scripts/ci/reflaxe-ocaml-runtime-reference-inventory.js',
		regenerationCommand: `node scripts/ci/reflaxe-ocaml-runtime-reference-inventory.js --write --review-bead ${reviewBead}`,
		completionRule: 'This inventory must be empty before runtime-reference authority can be complete.',
		megaFileRisks: [{
			path: `${SOURCE_ROOT}/ast/OcamlBuilder.hx`,
			migrationFamily: 'builder-mega-file',
			rule: 'Move semantic-family construction into focused modules; do not centralize occurrence migration in OcamlBuilder.',
		}],
		counts: {
			total: entries.length,
			byDomain: countBy(entries, 'domain'),
			byMigrationFamily: countBy(entries, 'migrationFamily'),
		},
		inventoryRevision: inventoryRevision(entries),
		entries,
	}
}

function compareInventory(committed, actualRecords) {
	const failures = []
	if (committed.schema !== SCHEMA) failures.push(`unsupported inventory schema ${committed.schema}`)
	if (committed.model !== MODEL) failures.push(`unsupported inventory model ${committed.model}`)
	if (committed.authority !== 'migration-inventory-only') failures.push('inventory must not claim semantic authority')
	if (typeof committed.reviewBead !== 'string' || committed.reviewBead.length === 0) failures.push('inventory reviewBead is missing')
	const expected = buildInventory(actualRecords, committed.reviewBead || 'missing-review-bead')
	const committedById = new Map((committed.entries || []).map(entry => [entry.id, entry]))
	const expectedById = new Map(expected.entries.map(entry => [entry.id, entry]))

	for (const record of actualRecords) {
		const entry = stableEntry(record)
		if (!committedById.has(entry.id)) {
			failures.push(`new legacy runtime reference: ${record.path}:${record.line} ${record.domain} ${record.construction} ${record.symbol || '<opaque raw boundary>'}`)
		}
	}
	for (const entry of committed.entries || []) {
		if (!expectedById.has(entry.id)) failures.push(`inventory still lists a removed or changed legacy reference: ${entry.id}`)
	}
	if (JSON.stringify(committed) !== JSON.stringify(expected)) {
		if (failures.length === 0) failures.push('inventory summary or metadata does not match the deterministic source scan')
	}
	return failures
}

function validateReviewBead(reviewBead) {
	if (typeof reviewBead !== 'string' || !/^haxe[._]ocaml-[A-Za-z0-9.-]+$/.test(reviewBead)) {
		throw new Error('--write requires --review-bead with the active haxe.ocaml Bead ID')
	}
}

function readArg(name) {
	const index = process.argv.indexOf(name)
	return index === -1 ? null : process.argv[index + 1]
}

function main() {
	const records = discoverFromSourceMap(loadRepositorySourceMap())
	const absoluteInventoryPath = path.join(REPO_ROOT, INVENTORY_PATH)
	if (process.argv.includes('--write')) {
		const reviewBead = readArg('--review-bead')
		validateReviewBead(reviewBead)
		fs.writeFileSync(absoluteInventoryPath, `${JSON.stringify(buildInventory(records, reviewBead), null, 2)}\n`)
		console.log(`WROTE_REFLAXE_OCAML_RUNTIME_REFERENCE_INVENTORY entries=${records.length} reviewBead=${reviewBead}`)
		return
	}

	const committed = JSON.parse(fs.readFileSync(absoluteInventoryPath, 'utf8'))
	const failures = compareInventory(committed, records)
	if (failures.length > 0) {
		console.error('The private runtime-reference migration inventory changed.')
		for (const failure of failures) console.error(`- ${failure}`)
		console.error('Review the change, then regenerate explicitly with an active Bead:')
		console.error('node scripts/ci/reflaxe-ocaml-runtime-reference-inventory.js --write --review-bead <bead-id>')
		process.exit(1)
	}
	console.log(`REFLAXE_OCAML_RUNTIME_REFERENCE_INVENTORY:PASS entries=${records.length} revision=${committed.inventoryRevision}`)
}

if (require.main === module) main()

module.exports = {
	SCHEMA,
	MODEL,
	maskHaxeComments,
	discoverFromSourceMap,
	buildInventory,
	compareInventory,
	validateReviewBead,
}
