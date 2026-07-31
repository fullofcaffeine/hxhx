import haxe.ds.StringMap;

private typedef DependencyTestSource = {
	final modulePath:String;
	final filePath:String;
	final source:String;
};

/**
	Focused proof that dependency observation uses sealed target-neutral typed facts.

	The fixture checks ordinary signature use, inline bodies, embeddable constants,
	static-initializer relationships, deterministic graph ordering, and the
	public-interface versus implementation revision split. It does not enable
	typed-module reuse.
**/
class M14CompilerDependencyObservationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function typedProgram(apiSource:String, mainSource:String):{modules:Array<TypedModule>, index:TyperIndex} {
		return typedSources([
			{modulePath: "Api", filePath: "Api.hx", source: apiSource},
			{modulePath: "Main", filePath: "Main.hx", source: mainSource}
		]);
	}

	static function typedSources(sources:Array<DependencyTestSource>):{modules:Array<TypedModule>, index:TyperIndex} {
		final resolved = [
			for (source in sources)
				new ResolvedModule(source.modulePath, source.filePath, ParserStage.parse(source.source, source.filePath))
		];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		return {
			modules: [
				for (module in resolved)
					TyperStage.typeResolvedModule(module, index, loader, true)
			],
			index: index
		};
	}

	static function moduleRevision(program:{modules:Array<TypedModule>, index:TyperIndex}, modulePath:String):CompilerTypedModuleRevision {
		final revision = CompilerDependencyCollector.collect(program.modules, program.index).findModule(modulePath);
		if (revision == null)
			throw 'missing typed module revision $modulePath';
		return revision;
	}

	static function hasEdge(snapshot:CompilerDependencySnapshot, kind:CompilerDependencyKind, factPart:String):Bool {
		return hasEdgeBetween(snapshot, "Main", "Api", kind, factPart);
	}

	static function hasEdgeBetween(snapshot:CompilerDependencySnapshot, consumer:String, provider:String, kind:CompilerDependencyKind, factPart:String):Bool {
		for (edge in snapshot.getEdges())
			if (edge.consumerModule == consumer
				&& edge.providerModule == provider
				&& CompilerDependencyKindTools.name(edge.kind) == CompilerDependencyKindTools.name(kind)
				&& edge.factIdentity.indexOf(factPart) >= 0)
				return true;
		return false;
	}

	static function edgePhase(snapshot:CompilerDependencySnapshot, kind:CompilerDependencyKind, factPart:String):Null<String> {
		return edgePhaseBetween(snapshot, "Main", "Api", kind, factPart);
	}

	static function edgePhaseBetween(snapshot:CompilerDependencySnapshot, consumer:String, provider:String, kind:CompilerDependencyKind,
			factPart:String):Null<String> {
		for (edge in snapshot.getEdges())
			if (edge.consumerModule == consumer
				&& edge.providerModule == provider
				&& CompilerDependencyKindTools.name(edge.kind) == CompilerDependencyKindTools.name(kind)
				&& edge.factIdentity.indexOf(factPart) >= 0)
				return CompilerDependencyPhaseTools.name(edge.phase);
		return null;
	}

	static function hasAnyEdgeBetween(snapshot:CompilerDependencySnapshot, consumer:String, provider:String, kind:CompilerDependencyKind):Bool {
		for (edge in snapshot.getEdges())
			if (edge.consumerModule == consumer
				&& edge.providerModule == provider
				&& CompilerDependencyKindTools.name(edge.kind) == CompilerDependencyKindTools.name(kind))
				return true;
		return false;
	}

	static function typedFunction(modules:Array<TypedModule>, modulePath:String, functionName:String):TypedFunction {
		for (module in modules) {
			if (CompilerTypedModuleRevision.semanticModulePath(module) != modulePath)
				continue;
			for (typedClass in module.getTypedClasses())
				for (typedFunction in typedClass.getFunctions())
					if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == functionName)
						return typedFunction;
		}
		throw 'missing typed function $modulePath.$functionName';
	}

	static function functionIdentity(modules:Array<TypedModule>, modulePath:String, functionName:String):String
		return typedFunction(modules, modulePath, functionName).getStableIdentity();

	static function functionBodyRevision(modules:Array<TypedModule>, modulePath:String, functionName:String):String
		return CompilerTypedTreeRevision.functionBody(typedFunction(modules, modulePath, functionName));

	static function typedProgramRevision(modules:Array<TypedModule>, macroMode:Bool = false):String
		return new MacroExpandedProgram(modules, macroMode).getTypedProgramRevision().getCanonicalIdentity();

	static function assertFunctionBodyRevisionPreservesTreeBoundaries():Void {
		final position = new HxPos(0, 1, 1);
		final declaration = new HxFunctionDecl("ambiguous", HxVisibility.Private, true, [], "Void", [], "", [], position);
		final fingerprint = TypedBodyFingerprint.forStatements([]);
		final first = new TypedFunction("RevisionFixture", 0, declaration, null, null, new TypedFunctionBody([
			TypedStmt.block([
				TypedStmt.block([TypedStmt.returnVoid(position)], position),
				TypedStmt.returnVoid(position),
			], position)
		], fingerprint));
		final second = new TypedFunction("RevisionFixture", 0, declaration, null, null, new TypedFunctionBody([
			TypedStmt.block([
				TypedStmt.block([TypedStmt.returnVoid(position), TypedStmt.returnVoid(position),], position)
			], position)
		], fingerprint));
		assertTrue(CompilerTypedTreeRevision.functionBody(first) != CompilerTypedTreeRevision.functionBody(second),
			"exact body revisions must preserve variable-length typed-tree boundaries");
	}

	static function visitExpression(expression:TypedExpr, visit:TypedExpr->Void):Void {
		visit(expression);
		for (child in expression.getExpressions())
			visitExpression(child, visit);
	}

	static function visitStatement(statement:TypedStmt, visit:TypedExpr->Void):Void {
		for (expression in statement.getExpressions())
			visitExpression(expression, visit);
		for (child in statement.getStatements())
			visitStatement(child, visit);
	}

	static function main():Void {
		assertFunctionBodyRevisionPreservesTreeBoundaries();
		final apiA = [
			"class Api {",
			"  public static function answer():Int return 42;",
			"  public static inline function twice(value:Int):Int return value * 2;",
			"  private static function hidden():Int return 1;",
			"}"
		].join("\n");
		final mainSource = [
			"import Api;",
			"class Main {",
			"  public static function main():Void {",
			"    var answer:Int = Api.answer();",
			"    var doubled:Int = Api.twice(answer);",
			"  }",
			"}"
		].join("\n");
		final first = typedProgram(apiA, mainSource);
		final snapshot = CompilerDependencyCollector.collect(first.modules, first.index);
		assertTrue(hasEdge(snapshot, CompilerDependencyKind.ModuleResolution, "import-normal:Api"),
			"an ordinary import should record both its source meaning and selected provider module");
		assertTrue(hasEdge(snapshot, CompilerDependencyKind.PublicInterface, "answer"), "ordinary call should depend on the selected public declaration");
		assertTrue(hasEdge(snapshot, CompilerDependencyKind.InlineImplementation, "twice"), "inline call should depend on the selected declaration body");
		assertTrue(edgePhase(snapshot, CompilerDependencyKind.ModuleResolution, "import-normal:Api") == "module-resolution",
			"an import dependency should name module resolution as its owning compiler phase");
		assertTrue(edgePhase(snapshot, CompilerDependencyKind.PublicInterface, "answer") == "shared-typing",
			"an exact call dependency should name shared typing as its owning compiler phase");

		final staticInitializerProgram = typedSources([
			{
				modulePath: "InitApi",
				filePath: "InitApi.hx",
				source: [
					"class InitApi {",
					"  public static var mutable:Int = 1;",
					"  public function new() {}",
					"  public static function make():Int return mutable;",
					"}"
				].join("\n")
			},
			{
				modulePath: "StaticInitializerConsumer",
				filePath: "StaticInitializerConsumer.hx",
				source: [
					"class StaticInitializerConsumer {",
					"  public static var fromCall:Int = InitApi.make();",
					"  public static var fromField:Int = InitApi.mutable;",
					"  public static var fromNew:InitApi = new InitApi();",
					"}"
				].join("\n")
			},
			{
				modulePath: "InstanceInitializerConsumer",
				filePath: "InstanceInitializerConsumer.hx",
				source: "class InstanceInitializerConsumer { public var fromCall:Int = InitApi.make(); }"
			}
		]);
		final staticInitializerSnapshot = CompilerDependencyCollector.collect(staticInitializerProgram.modules, staticInitializerProgram.index);
		assertTrue(hasEdgeBetween(staticInitializerSnapshot, "StaticInitializerConsumer", "InitApi", CompilerDependencyKind.StaticInitialization,
			"initializer:StaticInitializerConsumer#static#fromCall->declaration:"),
			"a static field initializer call should retain both the initializer field and exact selected declaration");
		assertTrue(hasEdgeBetween(staticInitializerSnapshot, "StaticInitializerConsumer", "InitApi", CompilerDependencyKind.StaticInitialization,
			"initializer:StaticInitializerConsumer#static#fromField->field:InitApi#static#mutable"),
			"a mutable static field read should retain an initialization edge even though its value is not an embeddable constant");
		assertTrue(hasEdgeBetween(staticInitializerSnapshot, "StaticInitializerConsumer", "InitApi", CompilerDependencyKind.StaticInitialization,
			"initializer:StaticInitializerConsumer#static#fromNew->type:InitApi"),
			"constructing a provider type during static initialization should retain its exact nominal identity");
		assertTrue(edgePhaseBetween(staticInitializerSnapshot, "StaticInitializerConsumer", "InitApi", CompilerDependencyKind.StaticInitialization,
			"fromCall") == "shared-typing",
			"a static-initialization edge should name the phase that selected its declaration and type facts");
		assertTrue(!hasAnyEdgeBetween(staticInitializerSnapshot, "InstanceInitializerConsumer", "InitApi", CompilerDependencyKind.StaticInitialization),
			"an instance field initializer should keep ordinary dependencies without being mislabeled as program static initialization");

		final aliasProgram = typedSources([
			{
				modulePath: "model.Api",
				filePath: "model/Api.hx",
				source: [
					"package model;",
					"class Api {",
					"  public static var count:Int = 3;",
					"  public function new() {}",
					"  public static function make():Api return new Api();",
					"}"
				].join("\n")
			},
			{
				modulePath: "AliasMain",
				filePath: "AliasMain.hx",
				source: [
					"import model.Api as Service;",
					"import model.Api.count;",
					"using model.Api;",
					"class AliasMain {",
					"  public static var cached:Service;",
					"  public static function use(items:Array<Service>):Service {",
					"    var created:Service = new Service();",
					"    var made:Service = Service.make();",
					"    var count:Int = Service.count;",
					"    return created;",
					"  }",
					"}"
				].join("\n")
			}
		]);
		final aliasMainInfo = aliasProgram.index.getByFullName("AliasMain");
		assertTrue(aliasMainInfo.fieldType("cached").getSemanticKey().indexOf("nominal:model.Api") >= 0,
			"an alias used as a field type should retain the provider's exact semantic type");
		final aliasUse = aliasMainInfo.getDeclarations().filter(declaration -> declaration.getSignature().getName() == "use")[0];
		assertTrue(aliasUse.getSignature().getArgs()[0].getSemanticKey().indexOf("nominal:model.Api") >= 0,
			"an alias nested inside a generic argument should retain the provider's exact semantic type");
		assertTrue(aliasUse.getSignature()
			.getReturnType()
			.getSemanticKey()
			.indexOf("nominal:model.Api") >= 0,
			"an alias used as a return type should retain the provider's exact semantic type");
		var sawAliasConstructor = false;
		var sawAliasStaticCall = false;
		var sawAliasStaticField = false;
		final aliasFunction = aliasProgram.modules.filter(module ->
			CompilerTypedModuleRevision.semanticModulePath(module) == "AliasMain")[0].getTypedClasses()[0].getFunctions()
		.filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == "use")[0];
		for (statement in aliasFunction.getBody().getStatements())
			visitStatement(statement, expression -> {
				final nominal = expression.getType().getNominalIdentity();
				if (expression.getTag() == NewValue && nominal != null && nominal.getCanonicalName() == "model.Api")
					sawAliasConstructor = true;
				final declaration = expression.getDeclaration();
				if (expression.getTag() == Call && declaration != null && declaration.getOwner().getCanonicalName() == "model.Api")
					sawAliasStaticCall = true;
				final field = expression.getFieldInfo();
				if (field != null && field.getOwner().getCanonicalName() == "model.Api" && field.getName() == "count")
					sawAliasStaticField = true;
			});
		assertTrue(sawAliasConstructor, "an aliased constructor should bind to the imported provider type");
		assertTrue(sawAliasStaticCall, "a static call through an alias should bind to the provider declaration");
		assertTrue(sawAliasStaticField, "a static field read through an alias should bind to the provider field");
		final aliasSnapshot = CompilerDependencyCollector.collect(aliasProgram.modules, aliasProgram.index);
		assertTrue(hasEdgeBetween(aliasSnapshot, "AliasMain", "model.Api", CompilerDependencyKind.ModuleResolution, "import-alias:model.Api:Service"),
			"an alias dependency should name its selected provider and local source name deterministically");
		assertTrue(hasEdgeBetween(aliasSnapshot, "AliasMain", "model.Api", CompilerDependencyKind.ModuleResolution, "import-normal:model.Api.count"),
			"a static-member import should depend on the type that owns the selected member");
		assertTrue(hasEdgeBetween(aliasSnapshot, "AliasMain", "model.Api", CompilerDependencyKind.ModuleResolution, "using:model.Api"),
			"a using directive should depend on its extension-provider type without becoming an ordinary type import");

		final resolvedTypeProgram = typedSources([
			{modulePath: "Model", filePath: "Model.hx", source: "class Model {}"},
			{modulePath: "Api", filePath: "Api.hx", source: "class Api { public static function echo(value:Model):Model return value; }"},
			{modulePath: "Main", filePath: "Main.hx", source: "class Main { public static function use(value:Model):Model return Api.echo(value); }"}
		]);
		final resolvedTypeSnapshot = CompilerDependencyCollector.collect(resolvedTypeProgram.modules, resolvedTypeProgram.index);
		assertTrue(hasEdgeBetween(resolvedTypeSnapshot, "Main", "Model", CompilerDependencyKind.PublicInterface, "signature:"),
			"a user-defined type selected in Main's public signature should record a Main-to-Model dependency");
		assertTrue(edgePhaseBetween(resolvedTypeSnapshot, "Main", "Model", CompilerDependencyKind.PublicInterface, "signature:") == "shared-typing",
			"a resolved semantic type dependency should name shared typing as its owning compiler phase");

		final reordered = CompilerDependencyCollector.collect([first.modules[1], first.modules[0]], first.index);
		assertTrue(snapshot.getCanonicalIdentity() == reordered.getCanonicalIdentity(),
			"equivalent module input order should produce one canonical dependency snapshot");
		assertTrue(typedProgramRevision(first.modules) == typedProgramRevision([first.modules[1], first.modules[0]]),
			"equivalent module input order should produce one exact typed-program revision");
		assertTrue(typedProgramRevision(first.modules) == typedProgramRevision([first.modules[0], first.modules[0], first.modules[1]]),
			"repeated equivalent type contributions should merge into one exact source-module revision");
		assertTrue(typedProgramRevision(first.modules) != typedProgramRevision([first.modules[0]]),
			"removing a typed module should change the exact program revision");
		assertTrue(typedProgramRevision(first.modules) != typedProgramRevision(first.modules, true),
			"macro-expanded and ordinary typed programs should have distinct exact revisions");

		final apiOrdinaryBodyChanged = apiA.split("return 42").join("return 43");
		final ordinaryChanged = typedProgram(apiOrdinaryBodyChanged, mainSource);
		final ordinaryRevision = CompilerDependencyCollector.collect(ordinaryChanged.modules, ordinaryChanged.index).findModule("Api");
		final originalRevision = snapshot.findModule("Api");
		assertTrue(originalRevision != null && ordinaryRevision != null, "Api revision should be present");
		assertTrue(originalRevision.publicInterfaceRevision == ordinaryRevision.publicInterfaceRevision,
			"ordinary body-only edit should retain the public-interface revision");
		assertTrue(originalRevision.implementationRevision != ordinaryRevision.implementationRevision,
			"ordinary body-only edit should change the implementation revision");
		assertTrue(typedProgramRevision(first.modules) != typedProgramRevision(ordinaryChanged.modules),
			"an implementation-only body edit should change the exact typed-program revision");
		var conflictingProgramRevisionRejected = false;
		try {
			typedProgramRevision([first.modules[0], ordinaryChanged.modules[0]]);
		} catch (_:Dynamic) {
			conflictingProgramRevisionRejected = true;
		}
		assertTrue(conflictingProgramRevisionRejected, "conflicting observations for one source module should fail before sealing a program revision");
		final repeatedFirst = typedProgram(apiA, mainSource);
		assertTrue(typedProgramRevision(first.modules) == typedProgramRevision(repeatedFirst.modules),
			"equivalent newly allocated typed programs should reproduce one exact revision");
		assertTrue(functionBodyRevision(first.modules, "Api", "answer") == functionBodyRevision(repeatedFirst.modules, "Api", "answer"),
			"equivalent newly allocated typed functions should reproduce one exact body revision");
		assertTrue(functionBodyRevision(first.modules, "Api", "answer") != functionBodyRevision(ordinaryChanged.modules, "Api", "answer"),
			"an ordinary semantic body edit should change the exact function-body revision");
		final exactAnswerProjection = typedFunction(first.modules, "Api", "answer");
		assertTrue(TypedBodySource.functionProjection(exactAnswerProjection)
			.getBodyRevision() == CompilerTypedTreeRevision.functionBody(exactAnswerProjection),
			"the strict backend projection should retain the exact body revision supplied by the typed owner");
		final identicalBodyFunctions = typedSources([
			{
				modulePath: "Twin",
				filePath: "Twin.hx",
				source: "class Twin { public static function first():Int return 1; public static function second():Int return 1; }"
			}
		]);
		assertTrue(functionBodyRevision(identicalBodyFunctions.modules, "Twin",
			"first") != functionBodyRevision(identicalBodyFunctions.modules, "Twin", "second"),
			"two declarations with identical statements should retain distinct body revisions");

		final apiInlineBodyChanged = apiA.split("value * 2").join("value * 3");
		final inlineChanged = typedProgram(apiInlineBodyChanged, mainSource);
		final inlineRevision = CompilerDependencyCollector.collect(inlineChanged.modules, inlineChanged.index).findModule("Api");
		assertTrue(inlineRevision != null && originalRevision.publicInterfaceRevision == inlineRevision.publicInterfaceRevision,
			"inline body edit should retain the general public-interface revision");
		assertTrue(originalRevision.implementationRevision != inlineRevision.implementationRevision,
			"inline body edit should change the implementation revision consumed only by inline-call edges");

		final ordinaryOnlyMain = [
			"import Api;",
			"class Main {",
			"  public static function main():Void {",
			"    var answer:Int = Api.answer();",
			"  }",
			"}"
		].join("\n");
		final ordinaryBefore = typedProgram(apiA, ordinaryOnlyMain);
		final ordinaryAfter = typedProgram(apiOrdinaryBodyChanged, ordinaryOnlyMain);
		final ordinaryComparison = CompilerDependencyInvalidator.compare(CompilerDependencyCollector.collect(ordinaryBefore.modules, ordinaryBefore.index),
			CompilerDependencyCollector.collect(ordinaryAfter.modules, ordinaryAfter.index));
		assertTrue(ordinaryComparison.isAffected("Api"), "edited module should always be affected");
		assertTrue(!ordinaryComparison.isAffected("Main"), "ordinary body edit should not invalidate a caller that consumes only its public signature");

		final inlineComparison = CompilerDependencyInvalidator.compare(snapshot,
			CompilerDependencyCollector.collect(inlineChanged.modules, inlineChanged.index));
		assertTrue(inlineComparison.isAffected("Main"), "inline body edit should invalidate the caller that embeds it");
		final inlineReason = inlineComparison.reasonFor("Main");
		assertTrue(inlineReason != null && inlineReason.describe().indexOf("inline-implementation") >= 0,
			"inline invalidation should explain the exact implementation-consuming edge");
		final importOnlyInlineAfter = typedProgram(apiInlineBodyChanged, ordinaryOnlyMain);
		final importOnlyInlineComparison = CompilerDependencyInvalidator.compare(CompilerDependencyCollector.collect(ordinaryBefore.modules,
			ordinaryBefore.index),
			CompilerDependencyCollector.collect(importOnlyInlineAfter.modules, importOnlyInlineAfter.index));
		assertTrue(!importOnlyInlineComparison.isAffected("Main"),
			"an inline body edit should not invalidate a module that imports Api but never calls the inline function");

		final apiSignatureChanged = apiA.split("answer():Int").join("answer():String");
		final signatureAfter = typedProgram(apiSignatureChanged, ordinaryOnlyMain);
		final signatureComparison = CompilerDependencyInvalidator.compare(CompilerDependencyCollector.collect(ordinaryBefore.modules, ordinaryBefore.index),
			CompilerDependencyCollector.collect(signatureAfter.modules, signatureAfter.index));
		assertTrue(signatureComparison.isAffected("Main"), "public signature edit should invalidate an ordinary caller");
		final signatureReason = signatureComparison.reasonFor("Main");
		assertTrue(signatureReason != null && signatureReason.describe().indexOf("public-interface:Main->Api") >= 0,
			"the caller must be reached through its public dependency instead of predicting itself after full retyping");

		final optionalApi = "class Api { public static function choose(?value:Int):Int return 1; }";
		final requiredApi = "class Api { public static function choose(value:Int):Int return 1; }";
		final optionalMain = "class Main { public static function main():Void { var value:Int = Api.choose(1); } }";
		final optionalBefore = typedProgram(optionalApi, optionalMain);
		final optionalAfter = typedProgram(requiredApi, optionalMain);
		final optionalBeforeRevision = CompilerDependencyCollector.collect(optionalBefore.modules, optionalBefore.index).findModule("Api");
		final optionalAfterRevision = CompilerDependencyCollector.collect(optionalAfter.modules, optionalAfter.index).findModule("Api");
		assertTrue(optionalBeforeRevision != null
			&& optionalAfterRevision != null
			&& optionalBeforeRevision.publicInterfaceRevision != optionalAfterRevision.publicInterfaceRevision,
			"changing an optional argument to required should change the public interface");
		assertTrue(functionIdentity(optionalBefore.modules, "Api", "choose") != functionIdentity(optionalAfter.modules, "Api", "choose"),
			"optional argument shape should participate in stable declaration identity");

		final restApi = "class Api { public static function collect(...values:Int):Int return 1; }";
		final ordinaryArgApi = "class Api { public static function collect(values:Int):Int return 1; }";
		final restMain = "class Main { public static function main():Void { var value:Int = Api.collect(1); } }";
		final restBefore = typedProgram(restApi, restMain);
		final restAfter = typedProgram(ordinaryArgApi, restMain);
		final restBeforeRevision = CompilerDependencyCollector.collect(restBefore.modules, restBefore.index).findModule("Api");
		final restAfterRevision = CompilerDependencyCollector.collect(restAfter.modules, restAfter.index).findModule("Api");
		assertTrue(restBeforeRevision != null
			&& restAfterRevision != null
			&& restBeforeRevision.publicInterfaceRevision != restAfterRevision.publicInterfaceRevision,
			"changing a rest argument to ordinary should change the public interface");
		assertTrue(functionIdentity(restBefore.modules, "Api", "collect") != functionIdentity(restAfter.modules, "Api", "collect"),
			"rest argument shape should participate in stable declaration identity");

		final constantAa = typedProgram('class Api { public static final label:String = "Aa"; }', mainSource);
		final constantBB = typedProgram('class Api { public static final label:String = "BB"; }', mainSource);
		assertTrue(moduleRevision(constantAa, "Api").publicInterfaceRevision == moduleRevision(constantBB, "Api").publicInterfaceRevision,
			"a constant value edit should not change the module-wide field name and type interface");
		assertTrue(moduleRevision(constantAa, "Api").implementationRevision != moduleRevision(constantBB, "Api").implementationRevision,
			"different constant text must remain distinct implementation input without the 32-bit lifecycle fingerprint");
		final constantReader = typedSources([
			{modulePath: "Api", filePath: "Api.hx", source: 'class Api { public static final label:String = "Aa"; }'},
			{modulePath: "Main", filePath: "Main.hx", source: "class Main { public static function value():String return Api.label; }"}
		]);
		final constantReaderSnapshot = CompilerDependencyCollector.collect(constantReader.modules, constantReader.index);
		assertTrue(hasEdge(constantReaderSnapshot, CompilerDependencyKind.ConstantValue, "field:Api#static#label"),
			"a qualified static final read should record the exact embeddable field identity");
		assertTrue(edgePhase(constantReaderSnapshot, CompilerDependencyKind.ConstantValue, "field:Api#static#label") == "shared-typing",
			"a selected constant field should name shared typing as its owning compiler phase");
		final qualifiedConstantReader = typedSources([
			{modulePath: "pkg.Api", filePath: "pkg/Api.hx", source: 'package pkg; class Api { public static final label:String = "Aa"; }'},
			{modulePath: "Main", filePath: "Main.hx", source: "class Main { public static function value():String return pkg.Api.label; }"}
		]);
		assertTrue(hasEdgeBetween(CompilerDependencyCollector.collect(qualifiedConstantReader.modules, qualifiedConstantReader.index), "Main", "pkg.Api",
			CompilerDependencyKind.ConstantValue, "field:pkg.Api#static#label"),
			"a fully qualified static constant read should retain the exact selected field even when its receiver child is not independently typable");
		final inlineFieldReader = typedSources([
			{modulePath: "Api", filePath: "Api.hx", source: 'class Api { public static inline var label:String = "Aa"; }'},
			{modulePath: "Main", filePath: "Main.hx", source: "class Main { public static function value():String return Api.label; }"}
		]);
		assertTrue(hasEdge(CompilerDependencyCollector.collect(inlineFieldReader.modules, inlineFieldReader.index), CompilerDependencyKind.ConstantValue,
			"field:Api#static#label"),
			"a qualified static inline field read should record the exact embeddable field identity");
		final mutableFieldReader = typedSources([
			{modulePath: "Api", filePath: "Api.hx", source: "class Api { public static var mutable:Int = 1; }"},
			{modulePath: "Main", filePath: "Main.hx", source: "class Main { public static function value():Int return Api.mutable; }"}
		]);
		final mutableFieldSnapshot = CompilerDependencyCollector.collect(mutableFieldReader.modules, mutableFieldReader.index);
		assertTrue(hasEdge(mutableFieldSnapshot, CompilerDependencyKind.PublicInterface, "expression-type:Api"),
			"a qualified mutable field read should retain a public-interface dependency on its resolved owner type");
		assertTrue(!hasEdge(mutableFieldSnapshot, CompilerDependencyKind.ConstantValue, "field:Api#static#mutable"),
			"a mutable field read should not claim that its initializer value was embedded");
		final sameClassReader = typedSources([
			{
				modulePath: "Api",
				filePath: "Api.hx",
				source: 'class Api { public static final label:String = "Aa"; public static function own():String return label; }'
			}
		]);
		final sameClassSnapshot = CompilerDependencyCollector.collect(sameClassReader.modules, sameClassReader.index);
		assertTrue(!hasEdgeBetween(sameClassSnapshot, "Api", "Api", CompilerDependencyKind.ConstantValue, "field:Api#static#label"),
			"a same-class constant read should resolve safely without creating a redundant self-dependency");
		final inferredInt = typedProgram("class Api { public static var value = 1; }", mainSource);
		final inferredString = typedProgram('class Api { public static var value = "one"; }', mainSource);
		assertTrue(moduleRevision(inferredInt, "Api").publicInterfaceRevision != moduleRevision(inferredString, "Api").publicInterfaceRevision,
			"an initializer change must conservatively change the public identity while a field's inferred type is not represented exactly");

		final inlineAa = typedProgram('class Api { public static inline function label():String return "Aa"; }', mainSource);
		final inlineBB = typedProgram('class Api { public static inline function label():String return "BB"; }', mainSource);
		assertTrue(moduleRevision(inlineAa, "Api").implementationRevision != moduleRevision(inlineBB, "Api").implementationRevision,
			"different inline typed bodies must not collide through the 32-bit lifecycle fingerprint");

		final thingA = "package a; class Thing {}";
		final thingB = "package b; class Thing {}";
		final apiUsesA = typedSources([
			{modulePath: "a.Thing", filePath: "a/Thing.hx", source: thingA},
			{modulePath: "b.Thing", filePath: "b/Thing.hx", source: thingB},
			{modulePath: "Api", filePath: "Api.hx", source: "import a.Thing; class Api { public static var value:Thing; }"}
		]);
		final apiUsesB = typedSources([
			{modulePath: "a.Thing", filePath: "a/Thing.hx", source: thingA},
			{modulePath: "b.Thing", filePath: "b/Thing.hx", source: thingB},
			{modulePath: "Api", filePath: "Api.hx", source: "import b.Thing; class Api { public static var value:Thing; }"}
		]);
		assertTrue(moduleRevision(apiUsesA, "Api").publicInterfaceRevision != moduleRevision(apiUsesB, "Api").publicInterfaceRevision,
			"a public field must record the resolved type selected by imports, not only the source word Thing");

		var duplicateRejected = false;
		try {
			new CompilerDependencySnapshot([
				new CompilerTypedModuleRevision("Api", "public-a", "implementation-a"),
				new CompilerTypedModuleRevision("Api", "public-b", "implementation-b")
			], []);
		} catch (_) {
			duplicateRejected = true;
		}
		assertTrue(duplicateRejected, "a snapshot must reject duplicate module identities instead of silently choosing one");
		final repeated = new CompilerTypedModuleRevision("Repeated", "public", "implementation", "source");
		final repeatedSnapshot = new CompilerDependencySnapshot([repeated, repeated], []);
		assertTrue(repeatedSnapshot.getModules().length == 1, "equivalent repeated observations of one logical module should coalesce deterministically");
		final secondaryA = new CompilerTypedModuleRevision("MultiType", "public-a", "implementation-a", "source");
		final secondaryB = new CompilerTypedModuleRevision("MultiType", "public-b", "implementation-b", "source");
		final mergedAB = CompilerTypedModuleRevision.mergeContributions("MultiType", [secondaryA, secondaryB]);
		final mergedBA = CompilerTypedModuleRevision.mergeContributions("MultiType", [secondaryB, secondaryA, secondaryA]);
		assertTrue(mergedAB.sourceRevision == mergedBA.sourceRevision
			&& mergedAB.publicInterfaceRevision == mergedBA.publicInterfaceRevision
			&& mergedAB.implementationRevision == mergedBA.implementationRevision,
			"secondary types from one Haxe module should merge as one order-independent set of exact contributions");
		var conflictingSourceRejected = false;
		try {
			CompilerTypedModuleRevision.mergeContributions("MultiType", [
				secondaryA,
				new CompilerTypedModuleRevision("MultiType", "public-c", "implementation-c", "other-source")
			]);
		} catch (_) {
			conflictingSourceRejected = true;
		}
		assertTrue(conflictingSourceRejected, "secondary-type aggregation must reject observations that claim one module path came from different source text");
		final emptyGeneratedDeclarations = CompilerGeneratedDeclarationObservation.empty();
		assertTrue(emptyGeneratedDeclarations == CompilerGeneratedDeclarationObservation.empty()
			&& emptyGeneratedDeclarations.getGeneratedMemberCount() == 0,
			"ordinary modules should share one immutable empty generated-declaration observation without hashing per module");
		var conflictingGeneratedDeclarationsRejected = false;
		try {
			CompilerTypedModuleRevision.mergeContributions("MultiType", [
				new CompilerTypedModuleRevision("MultiType", "public", "implementation", "source", null, null,
					CompilerConditionalCompilationObservation.empty(),
					CompilerGeneratedDeclarationObservation.fromGeneratedMemberSnippets(["private-generated-a"])),
				new CompilerTypedModuleRevision("MultiType", "public", "implementation", "source", null, null,
					CompilerConditionalCompilationObservation.empty(),
					CompilerGeneratedDeclarationObservation.fromGeneratedMemberSnippets(["private-generated-b"]))
			]);
		} catch (_) {
			conflictingGeneratedDeclarationsRejected = true;
		}
		assertTrue(conflictingGeneratedDeclarationsRejected, "secondary-type aggregation must reject two generated-declaration results for one source module");

		Sys.println("COMPILER_DEPENDENCY_OBSERVATION:PASS");
	}
}
