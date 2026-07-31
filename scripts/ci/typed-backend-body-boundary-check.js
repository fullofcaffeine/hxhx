#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "../..");
const roots = [
  path.join(repoRoot, "packages/hxhx-core/src/backend"),
  path.join(repoRoot, "packages/hxhx-core/src/EmitterStage.hx"),
  path.join(repoRoot, "packages/hxhx-core/src/TypedBodySource.hx"),
];

function haxeFiles(entry) {
  const stat = fs.statSync(entry);
  if (stat.isFile()) return entry.endsWith(".hx") ? [entry] : [];
  const out = [];
  for (const name of fs.readdirSync(entry).sort()) {
    out.push(...haxeFiles(path.join(entry, name)));
  }
  return out;
}

const files = roots.flatMap(haxeFiles);
const failures = [];

function requireFragment(relative, fragment, claim) {
  const source = fs.readFileSync(path.join(repoRoot, relative), "utf8");
  if (!source.includes(fragment)) failures.push(`${relative}: missing ${claim}`);
}

function rejectFragment(relative, fragment, claim) {
  const source = fs.readFileSync(path.join(repoRoot, relative), "utf8");
  if (source.includes(fragment)) failures.push(`${relative}: ${claim}`);
}

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const relative = path.relative(repoRoot, file);

  const rawBodyRead = /\bHxFunctionDecl\.getBodyText\s*\(|\.bodyText\b/g;
  for (const match of source.matchAll(rawBodyRead)) {
    failures.push(`${relative}:${source.slice(0, match.index).split("\n").length}: parsed raw function-body read`);
  }

  const direct = /\b[A-Za-z_][A-Za-z0-9_]*\.getParsed\(\)\.getDecl\(\)/g;
  for (const match of source.matchAll(direct)) {
    failures.push(`${relative}:${source.slice(0, match.index).split("\n").length}: direct parsed declaration read`);
  }

  const alias = /\b(?:final|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[A-Za-z_][A-Za-z0-9_]*\.getParsed\(\)\s*;/g;
  for (const match of source.matchAll(alias)) {
    const aliasName = match[1];
    const remainder = source.slice(match.index + match[0].length);
    const declarationRead = new RegExp(`\\b${aliasName}\\.getDecl\\(\\)`);
    if (declarationRead.test(remainder)) {
      failures.push(`${relative}:${source.slice(0, match.index).split("\n").length}: parsed alias \`${aliasName}\` reaches getDecl()`);
    }
  }

  if (
    relative !== "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx" &&
    source.includes(".requireSemanticFacts(")
  ) {
    failures.push(`${relative}: observation-only typed class facts reached a production backend before a target-owned plan cut`);
  }
  if (
    relative !== "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx" &&
    relative !== "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx" &&
    source.includes(".getClassGraph(")
  ) {
    failures.push(`${relative}: observation-only exact class graph reached a production backend before a target-owned plan cut`);
  }
  if (
    relative !== "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx" &&
    source.includes(".requireFunctionLoweringPlan(")
  ) {
    failures.push(`${relative}: observation-only PHP function plan reached a production backend before the function-renderer hard cut`);
  }
}

requireFragment(
  "packages/hxhx-core/src/CompilerTypedTreeRevision.hx",
  "public static function functionBody(typedFunction:TypedFunction):String",
  "target-neutral typed function-body revision owner",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendFunctionProjection.hx",
  "public function getBodyRevision():String",
  "strict backend projection body-revision accessor",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendFunctionProjection.hx",
  "public function getParameterBindingIdentities():Array<String>",
  "strict backend projection parameter-binding order",
);
requireFragment(
  "packages/hxhx-core/src/TypedBodySource.hx",
  "CompilerTypedTreeRevision.functionBody(typedFunction)",
  "sealed typed body revision handoff to backend projection",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendClassSemanticFacts.hx",
  'return "typed-backend-class-semantic-facts-v5"',
  "versioned immutable typed backend class-fact schema",
);
requireFragment(
  "packages/hxhx-core/src/TyTypeParameterId.hx",
  '"type-parameter-identity-v1"',
  "scoped semantic type-parameter identity",
);
requireFragment(
  "packages/hxhx-core/src/TyType.hx",
  "public function getTypeParameterIdentity():Null<TyTypeParameterId>",
  "semantic type binder identity accessor",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendClassSemanticFacts.hx",
  "public function getSuperClassIdentity():Null<String>",
  "raw nominal superclass identity distinct from the applied superclass type",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendClassGraph.hx",
  'return "typed-backend-class-graph-v3"',
  "versioned immutable typed backend class graph",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendClassGraph.hx",
  "public function requireLineage(classIdentity:String):Array<TypedBackendClassGraphNode>",
  "strict exact-class inheritance traversal",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendClassGraph.hx",
  "public function requireSpecializedLineage(classIdentity:String):Array<TypedBackendSpecializedClassNode>",
  "structural generic inheritance specialization",
);
requireFragment(
  "packages/hxhx-core/src/TyNominalInfo.hx",
  "public function getFieldInfos():Array<TyFieldInfo>",
  "exact nominal field-fact projection",
);
requireFragment(
  "packages/hxhx-core/src/TypedBodySource.hx",
  "new TypedBackendClassSemanticFacts(semanticInfo, null)",
  "single-owner typed class semantic-fact handoff to backend projection",
);
requireFragment(
  "packages/hxhx-core/src/TypedBackendClassProjection.hx",
  "public function requireSemanticFacts():TypedBackendClassSemanticFacts",
  "strict backend class semantic-fact accessor",
);
requireFragment(
  "packages/hxhx-core/src/MacroExpandedProgram.hx",
  "CompilerTypedProgramRevision.fromTypedModules(this.typedModules, macroMode)",
  "target-neutral typed program revision owner",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx",
  "typedProgramRevision = program.getTypedProgramRevision()",
  "sealed typed program revision handoff to PHP projection",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpProgramRenderFacts.hx",
  'return "php-program-render-facts-v1"',
  "versioned immutable PHP program-fact schema",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx",
  "public function getProgramRenderFacts():PhpProgramRenderFacts",
  "PHP program-fact observation accessor",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx",
  "public function getClassGraph():TypedBackendClassGraph",
  "lazy exact class-graph observation accessor",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx",
  "return new PhpProgramRenderFacts(getProgramRevision()",
  "lazy PHP program-fact observation construction",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpModuleRenderFacts.hx",
  'return "php-module-render-facts-v2"',
  "versioned immutable PHP module-fact schema",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx",
  "public function getModuleRenderFacts(moduleIdentity:String):PhpModuleRenderFacts",
  "PHP module-fact observation accessor",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpModuleRenderFacts.hx",
  "PhpRuntimeSupportTypeAlias.qualifiedName(rawImport)",
  "resolved PHP module-alias observation",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpFunctionLoweringPlan.hx",
  'return "php-function-lowering-plan-v5"',
  "versioned immutable PHP function-plan schema",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpFunctionLoweringPlan.hx",
  "classGraph.requireSpecializedLineage(classIdentity)",
  "exact structurally specialized function-plan lineage",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpLexicalRenderScope.hx",
  "class PhpLexicalRenderScope",
  "request-owned PHP lexical render scope",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpLexicalRenderScope.hx",
  "public static function forFunction(plan:PhpFunctionLoweringPlan):PhpLexicalRenderScope",
  "validated PHP function-scope root factory",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpLexicalRenderScope.hx",
  "public function derive(childKind:PhpLexicalScopeKind):PhpLexicalRenderScope",
  "immutable PHP lexical child derivation",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpTypedProgramProjection.hx",
  "public function requireFunctionLoweringPlan(declaration:HxFunctionDecl, ?renderClassUsesThisValueSlot:Bool):PhpFunctionLoweringPlan",
  "strict observation-only PHP function-plan accessor",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpThisValueSlotFacts.hx",
  "public static function classNeedsValueSlot(functions:Array<TypedBackendFunctionProjection>):Bool",
  "class-wide PHP abstract-value carrier derivation from exact typed bodies",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpFunctionBodyRenderer.hx",
  "class PhpFunctionBodyRenderer",
  "request-owned PHP function-body renderer",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/PhpProgramBodyRenderer.hx",
  "class PhpProgramBodyRenderer",
  "request-owned PHP program and support renderer",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceFunctionRenderFrame.hx",
  "public static function forPhpRenderer(renderer:PhpFunctionBodyRenderer):SourceFunctionRenderFrame",
  "explicit PHP lexical frame root",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceNativeTarget.hx",
  "enum SourceNativeTarget",
  "source-target identity independent of the shared syntax kernel",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceFunctionRenderFrame.hx",
  "PhpFunction(renderer:PhpFunctionBodyRenderer, scope:PhpLexicalRenderScope)",
  "closed PHP function renderer and lexical-scope frame",
);
rejectFragment(
  "packages/hxhx-core/src/backend/source/PhpFunctionBodyRenderer.hx",
  "SourceTargetCommon.",
  "request-owned PHP facts renderer called back into the shared syntax kernel and recreated an OCaml module cycle",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  'case Program(Php):\n\t\t\t\tthrow "PHP function bodies require PhpFunctionBodyRenderer";',
  "fail-closed legacy PHP function-body entry",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "final functionRenderer = projections.requireFunctionBodyRenderer(programRenderer, fn, needsThisValueSlot);",
  "request-owned ordinary and support-function renderer",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "final mainRenderer = projections.requireProjectedFunctionBodyRenderer(programRenderer, strictMainFunction);",
  "request-owned selected-main renderer",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "projections.requireFieldInitializerRenderer(programRenderer, field)",
  "request-owned typed field-initializer renderer",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "PhpRuntimeSupportTypeAlias.qualifiedName(rawImport)",
  "shared legacy PHP runtime-alias spelling policy",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "final programFacts = projections.getProgramRenderFacts();",
  "exact PHP program facts bound into the request-owned program renderer",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "facts: projections.getModuleRenderFacts(module.moduleIdentity)",
  "exact PHP module facts bound into the request-owned program renderer",
);
rejectFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  ".requireSemanticFacts(",
  "observation-only typed class facts reached the production renderer before a target-owned plan cut",
);
requireFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "return new PhpProgramBodyRenderer(programFacts, moduleInputs, projections.getClassGraph(), legacy);",
  "exact class graph bound into the request-owned PHP program renderer",
);
rejectFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  ".requireFunctionLoweringPlan(",
  "observation-only PHP function plans reached the production renderer before the function-renderer hard cut",
);
rejectFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "PhpLexicalRenderScope.forFunction(",
  "observation-only PHP lexical scopes reached the production renderer before the function-renderer hard cut",
);
rejectFragment(
  "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx",
  "renderStmtsWithFrame(Program(Php)",
  "PHP production rendering can still enter the legacy program frame",
);

const sourceTargetCommon = fs.readFileSync(
  path.join(repoRoot, "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx"),
  "utf8",
);
const phpCompatibilityBodyStart = sourceTargetCommon.indexOf(
  "static function renderPhpSpecialHelperFunctionBody(",
);
const phpCompatibilityBodyEnd = sourceTargetCommon.indexOf(
  "\n\t/**\n\t\tCreate the mutable PHP scope",
  phpCompatibilityBodyStart,
);
if (phpCompatibilityBodyStart < 0 || phpCompatibilityBodyEnd < 0) {
  failures.push(
    "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: missing finite PHP compatibility-body quarantine",
  );
} else {
  const expectedCompatibilityBodyIdentities = [
    "MyAbstractCounter.fromInt",
    "MyAbstractCounter.getValue",
    "MyAbstractCounter.new",
    "MyHash.fromArray",
    "MyHash.fromStringArray",
    "MyHash.get",
    "MyHash.set",
    "MyHash.toString",
    "MySpecialString.new",
    "MySpecialString.substr",
    "TestLocalStatic.basic",
    "TestMapComprehension.testBasic",
    "TestMatch.testExtractors",
  ];
  const compatibilityBodySource = sourceTargetCommon.slice(
    phpCompatibilityBodyStart,
    phpCompatibilityBodyEnd,
  );
  const actualCompatibilityBodyIdentities = [
    ...compatibilityBodySource.matchAll(/case "([^"]+)":/g),
  ]
    .map((match) => match[1])
    .sort();
  if (
    actualCompatibilityBodyIdentities.length !==
      expectedCompatibilityBodyIdentities.length ||
    actualCompatibilityBodyIdentities.some(
      (identity, index) => identity !== expectedCompatibilityBodyIdentities[index],
    )
  ) {
    failures.push(
      "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: quarantined PHP compatibility-body identity list changed; retire an existing replacement through shared typed semantics instead of adding a target-side substitution",
    );
  }
  if (
    !sourceTargetCommon.includes(
      "PHP_COMPATIBILITY_BODY_REPLACEMENTS:QUARANTINED",
    )
  ) {
    failures.push(
      "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: PHP compatibility-body replacements lost their evidence-exclusion marker",
    );
  }
}

if (
  !sourceTargetCommon.includes(
    "static function phpStaticInitFallbackLines(",
  ) ||
  !sourceTargetCommon.includes(
    "This is not typed-body rendering: it replaces a known Stage3 bring-up",
  )
) {
  failures.push(
    "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: static-initializer compatibility substitution lost its explicit quarantine",
  );
}

const phpStaticInitCompatibilityStart = sourceTargetCommon.indexOf(
  "PHP_STATIC_INIT_COMPATIBILITY_IDENTITIES:BEGIN",
);
const phpStaticInitCompatibilityEnd = sourceTargetCommon.indexOf(
  "PHP_STATIC_INIT_COMPATIBILITY_IDENTITIES:END",
);
if (
  phpStaticInitCompatibilityStart < 0 ||
  phpStaticInitCompatibilityEnd <= phpStaticInitCompatibilityStart
) {
  failures.push(
    "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: static-initializer compatibility substitution lost its finite identity markers",
  );
} else {
  const expectedStaticInitCompatibilityIdentities = [
    "unit.PropBox#static:__init__()->unknown#0",
  ];
  const staticInitCompatibilitySource = sourceTargetCommon.slice(
    phpStaticInitCompatibilityStart,
    phpStaticInitCompatibilityEnd,
  );
  const actualStaticInitCompatibilityIdentities = [
    ...staticInitCompatibilitySource.matchAll(/case "([^"]+)":/g),
  ]
    .map((match) => match[1])
    .sort();
  if (
    actualStaticInitCompatibilityIdentities.length !==
      expectedStaticInitCompatibilityIdentities.length ||
    actualStaticInitCompatibilityIdentities.some(
      (identity, index) =>
        identity !== expectedStaticInitCompatibilityIdentities[index],
    )
  ) {
    failures.push(
      "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: quarantined PHP static-initializer identity list changed; retire the replacement through shared typed semantics instead of broadening it",
    );
  }
  if (
    !staticInitCompatibilitySource.includes(
      'case SExpr(EBinop("=", EIdent("STAT_X"), EInt(3)), _):',
    )
  ) {
    failures.push(
      "packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: quarantined PHP static-initializer replacement no longer requires its one exact assignment shape",
    );
  }
}

for (const retiredField of [
  "phpRenderLocalTypes",
  "phpRenderLocalInits",
  "phpRenderCurrentFunctionName",
  "phpRenderCurrentInstanceMethodNames",
  "phpRenderCurrentInstanceMethodArgs",
  "phpRenderSameClassMethodNames",
  "phpRenderSameClassFieldNames",
  "phpRenderSameClassFieldTypeHints",
  "phpRenderSameClassStaticFieldNames",
  "phpRenderSameClassName",
  "phpRenderSameClassLocals",
  "phpRenderStringExtensionMethodsByField",
  "phpRenderLocalEnumConstructors",
  "phpRenderPreferredEnumName",
  "phpRenderDynamicCallFieldsByLocal",
  "phpRenderRefCaptureLocals",
  "phpRenderThisValueSlot",
  "phpThisValueCaptureName",
  "phpRenderOptionalLambdaArgNamesByLocal",
  "phpRenderOptionalLambdaOptionalArgNamesByLocal",
  "phpRenderGenericConstructorSamples",
  "phpRenderInstanceMethodsByType",
  "phpRenderInstanceMethodArgsByType",
  "phpRenderInstanceFieldsByType",
  "phpRenderInstanceFieldTypeHintsByType",
  "phpRenderDynamicMethodsByType",
  "phpRenderStaticMethodsByType",
  "phpRenderStaticOverloadsByType",
  "phpRenderInstanceOverloadsByType",
  "phpRenderGenericStaticFunctionsByType",
  "phpRenderStaticCallableFieldsByType",
  "phpRenderClassBaseTypes",
  "phpRenderStringExtensionMethodsByClass",
  "phpRenderKnownTypeNames",
  "phpRenderAbstractTypeNames",
  "phpRenderEmittedTypeNames",
  "phpRenderLocalTypeNames",
  "phpRenderDuplicateTypeNames",
  "phpRenderInterfaceTypeNames",
  "phpRenderEnumConstructors",
  "phpRenderAmbiguousEnumConstructors",
  "phpRenderEnumConstructorsByEnum",
  "phpRenderEnumAbstractValues",
  "phpRenderAmbiguousEnumAbstractValues",
  "phpRenderTypeAliases",
]) {
  const declaration = new RegExp(`\\bstatic\\s+var\\s+${retiredField}\\b`);
  const reset = new RegExp(`\\b${retiredField}\\s*=\\s*null\\s*;`);
  if (declaration.test(sourceTargetCommon)) {
    failures.push(`packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: retired PHP function state ${retiredField} was redeclared`);
  }
  if (reset.test(sourceTargetCommon)) {
    failures.push(`packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: retired PHP function state ${retiredField} returned to request reset`);
  }
}
if (sourceTargetCommon.includes("public static function resetRequestState()")) {
  failures.push("packages/hxhx-core/src/backend/source/SourceTargetCommon.hx: retired source-target request-reset lifecycle was restored");
}

if (failures.length > 0) {
  console.error("Typed backend body boundary failed.");
  console.error("Backends must obtain declarations/function bodies from TypedModule.getBackendDeclaration().");
  console.error("TypedModule.getParsed() remains available only for file/source provenance.");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`TYPED_BACKEND_BODY_BOUNDARY:PASS files=${files.length}`);
