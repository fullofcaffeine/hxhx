import haxe.ds.StringMap;

private typedef DependencyTestSource = {
	final modulePath:String;
	final filePath:String;
	final source:String;
};

/**
	Focused proof that dependency observation uses sealed target-neutral typed facts.

	The fixture checks ordinary signature use, inline bodies, embeddable constants,
	deterministic graph ordering, and the public-interface versus implementation
	revision split. It does not enable typed-module reuse.
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

	static function functionIdentity(modules:Array<TypedModule>, modulePath:String, functionName:String):String {
		for (module in modules) {
			if (CompilerTypedModuleRevision.semanticModulePath(module) != modulePath)
				continue;
			for (typedClass in module.getTypedClasses())
				for (typedFunction in typedClass.getFunctions())
					if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == functionName)
						return typedFunction.getStableIdentity();
		}
		throw 'missing typed function $modulePath.$functionName';
	}

	static function main():Void {
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
		assertTrue(hasEdge(snapshot, CompilerDependencyKind.ModuleResolution, "import:Api"), "explicit import should record the selected provider module");
		assertTrue(hasEdge(snapshot, CompilerDependencyKind.PublicInterface, "answer"), "ordinary call should depend on the selected public declaration");
		assertTrue(hasEdge(snapshot, CompilerDependencyKind.InlineImplementation, "twice"), "inline call should depend on the selected declaration body");
		assertTrue(edgePhase(snapshot, CompilerDependencyKind.ModuleResolution, "import:Api") == "module-resolution",
			"an import dependency should name module resolution as its owning compiler phase");
		assertTrue(edgePhase(snapshot, CompilerDependencyKind.PublicInterface, "answer") == "shared-typing",
			"an exact call dependency should name shared typing as its owning compiler phase");

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

		final apiOrdinaryBodyChanged = apiA.split("return 42").join("return 43");
		final ordinaryChanged = typedProgram(apiOrdinaryBodyChanged, mainSource);
		final ordinaryRevision = CompilerDependencyCollector.collect(ordinaryChanged.modules, ordinaryChanged.index).findModule("Api");
		final originalRevision = snapshot.findModule("Api");
		assertTrue(originalRevision != null && ordinaryRevision != null, "Api revision should be present");
		assertTrue(originalRevision.publicInterfaceRevision == ordinaryRevision.publicInterfaceRevision,
			"ordinary body-only edit should retain the public-interface revision");
		assertTrue(originalRevision.implementationRevision != ordinaryRevision.implementationRevision,
			"ordinary body-only edit should change the implementation revision");

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

		Sys.println("COMPILER_DEPENDENCY_OBSERVATION:PASS");
	}
}
