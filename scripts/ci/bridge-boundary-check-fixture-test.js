#!/usr/bin/env node

const {
  readManifest,
  readSourceMap,
  validateRepositoryState,
} = require('./bridge-boundary-check.js')

function assertNoErrors(errors, label) {
  if (errors.length > 0) throw new Error(`${label}:\n- ${errors.join('\n- ')}`)
}

function assertRejected(baseSources, manifest, label, source, expectedText) {
  const sources = new Map(baseSources)
  sources.set(`packages/hxhx/src/hxhx/Fixture${label}.hx`, source)
  const errors = validateRepositoryState(sources, manifest)
  if (!errors.some(error => error.includes(expectedText))) {
    throw new Error(`${label}: expected an error containing ${JSON.stringify(expectedText)}, got:\n- ${errors.join('\n- ')}`)
  }
}

function main() {
  const sources = readSourceMap()
  const manifest = readManifest()
  assertNoErrors(validateRepositoryState(sources, manifest), 'repository baseline')

  assertRejected(
    sources,
    manifest,
    'BackendDispatch',
    'class FixtureBackendDispatch { static function run() BackendDispatchBoundary.emit(null, null, null); }',
    'BackendDispatchBoundary.emit call'
  )
  assertRejected(
    sources,
    manifest,
    'GenIrRecovery',
    'class FixtureGenIrRecovery { static function run(value:Dynamic) GenIrBoundary.fromDynamic(value); }',
    'GenIrBoundary.fromDynamic call'
  )
  assertRejected(
    sources,
    manifest,
    'UnlistedRevisionCheck',
    'class FixtureUnlistedRevisionCheck { static function run(program) GenIrBoundary.requireProgram(program); }',
    'GenIrBoundary.requireProgram call'
  )
  assertRejected(
    sources,
    manifest,
    'RawOcaml',
    'class FixtureRawOcaml { static function run() untyped __ocaml__("0"); }',
    'compiler source untyped __ocaml__ call'
  )
  assertRejected(
    sources,
    manifest,
    'SocketHelper',
    'class FixtureSocketHelper { static function run() NativeCompilerServer.connect("127.0.0.1:1", ""); }',
    'NativeCompilerServer.connect call'
  )
  assertRejected(
    sources,
    manifest,
    'DirectSocket',
    'class FixtureDirectSocket { static function run() { final socket = new sys.net.Socket(); } }',
    'direct sys.net.Socket use in current compiler source'
  )
  assertRejected(
    sources,
    manifest,
    'RetiredNativeParser',
    '@:native("HxHxNativeParser") extern class FixtureRetiredNativeParser {}',
    'handwritten native lexer/parser module must stay retired'
  )
  assertRejected(
    sources,
    manifest,
    'RetiredExpressionRewrite',
    'class FixtureRetiredExpressionRewrite { static function run(source:String) return HxParserSourceNormalize.normalizeDenseEscapedQuotes(source); }',
    'protocol-era expression source rewrite helper must stay retired'
  )

  // Inventorying the native wrapper must not authorize extra checks or casts.
  const nativePath = 'packages/hxhx-core/src/backend/ocaml/OcamlNativeTargetCore.hx'
  const nativeSource = sources.get(nativePath)
  for (const [label, source, expectedText] of [
    ['missing revision check', nativeSource.replace('GenIrBoundary.requireProgram(program)', 'program'),
      `GenIrBoundary.requireProgram call: expected 1 in ${nativePath}, found 0`],
    ['duplicate revision check', `${nativeSource}\nGenIrBoundary.requireProgram(program);`,
      `GenIrBoundary.requireProgram call: expected 1 in ${nativePath}, found 2`],
    ['unsafe input recovery', `${nativeSource}\nGenIrBoundary.fromDynamic(program);`,
      `GenIrBoundary.fromDynamic call: expected 0 in ${nativePath}, found 1`],
    ['unsafe output conversion', `${nativeSource}\nGenIrBoundary.asBackendProgram(program);`,
      `GenIrBoundary.asBackendProgram call: expected 0 in ${nativePath}, found 1`],
  ]) {
    const changedSources = new Map(sources)
    changedSources.set(nativePath, source)
    const errors = validateRepositoryState(changedSources, manifest)
    if (!errors.includes(expectedText)) {
      throw new Error(`${label}: expected ${expectedText}, got:\n- ${errors.join('\n- ')}`)
    }
  }

  const expandedManifest = JSON.parse(JSON.stringify(manifest))
  expandedManifest.bridges[0].allowedHaxeFiles.push('packages/hxhx/src/hxhx/QuietlyExpandedBoundary.hx')
  const manifestErrors = validateRepositoryState(sources, expandedManifest)
  if (!manifestErrors.some(error => error.includes('allowedHaxeFiles must be exactly'))) {
    throw new Error(`inventory expansion fixture was not rejected:\n- ${manifestErrors.join('\n- ')}`)
  }

  console.log('[ci:guards] OK: temporary bridge boundary negative fixtures pass')
}

main()
