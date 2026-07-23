import haxe.ds.StringMap;

private typedef DependencyEditSource = {
	final modulePath:String;
	final filePath:String;
	final source:String;
};

/**
	Proves shared and transitive dependency predictions across clean edit sequences.

	Every source version is parsed and typed from scratch. The observer still skips
	no compiler work; these assertions exercise only the affected-module prediction
	that must become trustworthy before typed-module reuse can begin.
**/
class M14CompilerDependencyEditSequenceTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function snapshot(sources:Array<DependencyEditSource>, reverseModules:Bool = false, ?originIndexByModule:StringMap<Int>):CompilerDependencySnapshot {
		final resolved = [
			for (source in sources) {
				final selectedIndex = originIndexByModule == null ? null : originIndexByModule.get(source.modulePath);
				new ResolvedModule(source.modulePath, source.filePath, ParserStage.parse(source.source, source.filePath),
					CompilerModuleOrigin.direct(source.modulePath, selectedIndex == null ? 0 : selectedIndex));
			}
		];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final modules = [
			for (module in resolved)
				TyperStage.typeResolvedModule(module, index, loader, true)
		];
		if (reverseModules)
			modules.reverse();
		return CompilerDependencyCollector.collect(modules, index);
	}

	static function sharedSources(sharedSource:String):Array<DependencyEditSource> {
		return [
			{modulePath: "Shared", filePath: "Shared.hx", source: sharedSource},
			{
				modulePath: "Left",
				filePath: "Left.hx",
				source: "class Left { public static inline function value():Dynamic return Shared.ordinary(); }"
			},
			{
				modulePath: "Right",
				filePath: "Right.hx",
				source: "class Right { public static function value():Dynamic return Shared.ordinary(); }"
			},
			{
				modulePath: "Main",
				filePath: "Main.hx",
				source: [
					"class Main {",
					"  public static function main():Void {",
					"    var left:Dynamic = Left.value();",
					"    var right:Dynamic = Right.value();",
					"  }",
					"}"
				].join("\n")
			}
		];
	}

	static function inlineSources(sharedSource:String):Array<DependencyEditSource> {
		return [
			{modulePath: "Shared", filePath: "Shared.hx", source: sharedSource},
			{
				modulePath: "Left",
				filePath: "Left.hx",
				source: "class Left { public static inline function value():Int return Shared.embedded(); }"
			},
			{
				modulePath: "Right",
				filePath: "Right.hx",
				source: "import Shared; class Right { public static function value():Int return 7; }"
			},
			{
				modulePath: "Main",
				filePath: "Main.hx",
				source: [
					"class Main {",
					"  public static function main():Void {",
					"    var left:Int = Left.value();",
					"    var right:Int = Right.value();",
					"  }",
					"}"
				].join("\n")
			}
		];
	}

	static function constantSources(apiSource:String):Array<DependencyEditSource> {
		return [
			{modulePath: "Api", filePath: "Api.hx", source: apiSource},
			{
				modulePath: "Main",
				filePath: "Main.hx",
				source: "class Main { public static function value():String return Api.label; }"
			},
			{
				modulePath: "ImportOnly",
				filePath: "ImportOnly.hx",
				source: "import Api; class ImportOnly { public static function value():Int return 0; }"
			},
			{
				modulePath: "MutableReader",
				filePath: "MutableReader.hx",
				source: "class MutableReader { public static function value():Int return Api.mutable; }"
			},
			{
				modulePath: "FieldReader",
				filePath: "FieldReader.hx",
				source: "class FieldReader { public static final copy:String = Api.label; }"
			}
		];
	}

	static function qualifiedConstantSources(value:String):Array<DependencyEditSource> {
		return [
			{
				modulePath: "pkg.Api",
				filePath: "pkg/Api.hx",
				source: 'package pkg; class Api { public static final label:String = "$value"; }'
			},
			{
				modulePath: "QualifiedReader",
				filePath: "QualifiedReader.hx",
				source: "class QualifiedReader { public static function value():String return pkg.Api.label; }"
			},
			{
				modulePath: "QualifiedFieldReader",
				filePath: "QualifiedFieldReader.hx",
				source: "class QualifiedFieldReader { public static final copy:String = pkg.Api.label; }"
			}
		];
	}

	static function affected(comparison:CompilerDependencyComparison):String
		return [for (invalidation in comparison.getInvalidations()) invalidation.modulePath].join(",");

	static function reasons(comparison:CompilerDependencyComparison):String
		return [for (invalidation in comparison.getInvalidations()) invalidation.describe()].join("\n");

	static function conditionalObservation(value:String):CompilerConditionalCompilationObservation {
		final defines = new StringMap<String>();
		defines.set("build_mode", value);
		return HxConditionalCompilation.filterSourceObserved([
			'#if build_mode == "enabled"',
			"class ConditionalProvider {}",
			"#else",
			"class ConditionalProvider {}",
			"#end"
		].join("\n"), defines).getObservation();
	}

	static function generatedObservation(value:String):CompilerGeneratedDeclarationObservation
		return CompilerGeneratedDeclarationObservation.fromGeneratedMemberSnippets([value]);

	static function main():Void {
		final sharedA = "class Shared { public static function ordinary():Int return 1; }";
		final sharedPublicB = 'class Shared { public static function ordinary():String return "one"; }';
		final sharedBodyB = "class Shared { public static function ordinary():Int return 2; }";
		final publicA = snapshot(sharedSources(sharedA));
		final publicB = snapshot(sharedSources(sharedPublicB));
		final publicComparison = CompilerDependencyInvalidator.compare(publicA, publicB);
		assertTrue(affected(publicComparison) == "Left,Main,Right,Shared",
			"a shared public change should reach both callers and the downstream inline consumer");
		final leftReason = publicComparison.reasonFor("Left");
		final rightReason = publicComparison.reasonFor("Right");
		assertTrue(leftReason != null && leftReason.describe().indexOf("public-interface:Left->Shared") >= 0,
			"the left caller should be reached through its real Shared declaration edge");
		assertTrue(rightReason != null && rightReason.describe().indexOf("public-interface:Right->Shared") >= 0,
			"the right caller should be reached through its real Shared declaration edge");
		final mainReason = publicComparison.reasonFor("Main");
		assertTrue(mainReason != null
			&& mainReason.describe().indexOf("public-interface:Left->Shared") >= 0
			&& mainReason.describe().indexOf("inline-implementation:Main->Left") >= 0,
			"the downstream reason should show the complete Shared-to-Left-to-Main path");

		final bodyB = snapshot(sharedSources(sharedBodyB));
		final bodyComparison = CompilerDependencyInvalidator.compare(publicA, bodyB);
		assertTrue(affected(bodyComparison) == "Shared", "an ordinary body-only edit should not invalidate signature-only callers");

		final movedOriginIndexes = new StringMap<Int>();
		movedOriginIndexes.set("Shared", 1);
		final sameBytesDifferentOrigin = snapshot(sharedSources(sharedA), false, movedOriginIndexes);
		final originComparison = CompilerDependencyInvalidator.compare(publicA, sameBytesDifferentOrigin);
		assertTrue(originComparison.getSourceOriginChanges().join(",") == "Shared",
			"the observer should distinguish equal source bytes selected from a different class-path slot");
		assertTrue(affected(originComparison) == "Shared",
			"an origin-only change should recheck the selected module without pretending its callers consumed different semantics");
		final originReason = originComparison.reasonFor("Shared");
		assertTrue(originReason != null
			&& originReason.describe().indexOf("source-origin-changed:Shared:Shared@classpath[0]->Shared@classpath[1]") >= 0,
			"the direct reason should explain the logical origin change without an absolute filesystem path");
		final originalOriginAgain = snapshot(sharedSources(sharedA));
		assertTrue(publicA.getCanonicalIdentity() == originalOriginAgain.getCanonicalIdentity(),
			"returning to the original source origin should reproduce the original dependency snapshot");

		final conditionalAObservation = conditionalObservation("private-a");
		final conditionalBObservation = conditionalObservation("private-b");
		final conditionalARevision = new CompilerTypedModuleRevision("ConditionalProvider", "public-same", "implementation-same", "source-same", null, null,
			conditionalAObservation);
		final conditionalBRevision = new CompilerTypedModuleRevision("ConditionalProvider", "public-same", "implementation-same", "source-same", null, null,
			conditionalBObservation);
		final conditionalA = new CompilerDependencySnapshot([conditionalARevision], []);
		final conditionalB = new CompilerDependencySnapshot([conditionalBRevision], []);
		final addedWithoutConditions = CompilerDependencyInvalidator.compare(new CompilerDependencySnapshot([], []),
			new CompilerDependencySnapshot([new CompilerTypedModuleRevision("Added", "public", "implementation", "source")], []));
		assertTrue(addedWithoutConditions.getConditionalCompilationChanges().length == 0,
			"adding a module with no #if expressions should not be mislabeled as a conditional-compilation change");
		final conditionalComparison = CompilerDependencyInvalidator.compare(conditionalA, conditionalB);
		assertTrue(conditionalComparison.getConditionalCompilationChanges().join(",") == "ConditionalProvider",
			"changing an evaluated compile-time define should be reported even when the selected parsed and typed module is identical");
		assertTrue(affected(conditionalComparison) == "ConditionalProvider",
			"an input-only conditional change should recheck its provider without pretending unchanged callers consumed new semantics");
		final conditionalReason = reasons(conditionalComparison);
		assertTrue(conditionalReason.indexOf("conditional-compilation-changed:ConditionalProvider:build_mode") >= 0,
			"the direct reason should name the evaluated define key");
		assertTrue(conditionalReason.indexOf("private-a") < 0 && conditionalReason.indexOf("private-b") < 0,
			"conditional invalidation reasons must not reveal raw define values");
		assertTrue(conditionalA.getCanonicalIdentity().indexOf("private-a") < 0
			&& conditionalB.getCanonicalIdentity().indexOf("private-b") < 0,
			"the long-lived dependency identity must not retain raw define values outside reports either");

		final conditionalConsumer = new CompilerTypedModuleRevision("ConditionalConsumer", "consumer-public", "consumer-implementation", "consumer-source");
		final conditionalPublicB = new CompilerTypedModuleRevision("ConditionalProvider", "public-b", "implementation-b", "source-b", null, null,
			conditionalBObservation);
		final conditionalEdge = new CompilerDependencyEdge("ConditionalConsumer", "ConditionalProvider", CompilerDependencyPhase.SharedTyping,
			CompilerDependencyKind.PublicInterface, "declaration:ConditionalProvider.answer");
		final conditionalPublicBefore = new CompilerDependencySnapshot([conditionalARevision, conditionalConsumer], [conditionalEdge]);
		final conditionalPublicAfter = new CompilerDependencySnapshot([conditionalPublicB, conditionalConsumer], [conditionalEdge]);
		final conditionalPublicComparison = CompilerDependencyInvalidator.compare(conditionalPublicBefore, conditionalPublicAfter);
		assertTrue(affected(conditionalPublicComparison) == "ConditionalConsumer,ConditionalProvider",
			"a conditional choice that changes the public interface should continue through ordinary caller dependencies");
		final conditionalConsumerReason = conditionalPublicComparison.reasonFor("ConditionalConsumer");
		assertTrue(conditionalConsumerReason != null
			&& conditionalConsumerReason.describe().indexOf("conditional-compilation-changed:ConditionalProvider:build_mode") >= 0
			&& conditionalConsumerReason.describe().indexOf("public-interface:ConditionalConsumer->ConditionalProvider") >= 0,
			"a propagated reason should retain both the compile-time input cause and the caller edge");
		final conditionalAAgain = new CompilerDependencySnapshot([
			new CompilerTypedModuleRevision("ConditionalProvider", "public-same", "implementation-same", "source-same", null, null,
				conditionalObservation("private-a"))
		], []);
		assertTrue(conditionalA.getCanonicalIdentity() == conditionalAAgain.getCanonicalIdentity(),
			"returning to exact conditional revision A should reproduce its dependency snapshot");
		assertTrue(reasons(CompilerDependencyInvalidator.compare(conditionalB, conditionalAAgain)) == conditionalReason,
			"conditional A-to-B-to-A comparisons should reproduce deterministic path-safe reasons");

		final generatedAObservation = generatedObservation("private-generated-a");
		final generatedBObservation = generatedObservation("private-generated-b");
		final generatedARevision = new CompilerTypedModuleRevision("GeneratedProvider", "public-same", "implementation-same", "source-same", null, null,
			CompilerConditionalCompilationObservation.empty(), generatedAObservation);
		final generatedImplementationBRevision = new CompilerTypedModuleRevision("GeneratedProvider", "public-same", "implementation-b", "source-same", null,
			null, CompilerConditionalCompilationObservation.empty(), generatedBObservation);
		final generatedA = new CompilerDependencySnapshot([generatedARevision], []);
		final generatedImplementationB = new CompilerDependencySnapshot([generatedImplementationBRevision], []);
		final addedWithoutGeneratedDeclarations = CompilerDependencyInvalidator.compare(new CompilerDependencySnapshot([], []),
			new CompilerDependencySnapshot([
				new CompilerTypedModuleRevision("AddedGeneratedControl", "public", "implementation", "source")
			], []));
		assertTrue(addedWithoutGeneratedDeclarations.getGeneratedDeclarationChanges().length == 0,
			"adding a module without build-macro output should not be mislabeled as a generated-declaration change");
		final generatedImplementationComparison = CompilerDependencyInvalidator.compare(generatedA, generatedImplementationB);
		assertTrue(generatedImplementationComparison.getGeneratedDeclarationChanges().join(",") == "GeneratedProvider",
			"changing build-macro output should be reported even when annotated source stays identical");
		assertTrue(affected(generatedImplementationComparison) == "GeneratedProvider",
			"an implementation-only generated change should recheck its provider without invalidating signature-only callers");
		final generatedReason = reasons(generatedImplementationComparison);
		assertTrue(generatedReason.indexOf("generated-declarations-changed:GeneratedProvider") >= 0,
			"the direct reason should identify the module whose generated declarations changed");
		assertTrue(generatedReason.indexOf("private-generated-a") < 0 && generatedReason.indexOf("private-generated-b") < 0,
			"generated-declaration reasons must not reveal macro output");
		assertTrue(generatedA.getCanonicalIdentity().indexOf("private-generated-a") < 0
			&& generatedImplementationB.getCanonicalIdentity().indexOf("private-generated-b") < 0,
			"the long-lived dependency identity must not retain raw generated member text");

		final generatedConsumer = new CompilerTypedModuleRevision("GeneratedConsumer", "consumer-public", "consumer-implementation", "consumer-source");
		final generatedPublicBRevision = new CompilerTypedModuleRevision("GeneratedProvider", "public-b", "implementation-b", "source-same", null, null,
			CompilerConditionalCompilationObservation.empty(), generatedBObservation);
		final generatedEdge = new CompilerDependencyEdge("GeneratedConsumer", "GeneratedProvider", CompilerDependencyPhase.SharedTyping,
			CompilerDependencyKind.PublicInterface, "declaration:GeneratedProvider.answer");
		final generatedPublicBefore = new CompilerDependencySnapshot([generatedARevision, generatedConsumer], [generatedEdge]);
		final generatedPublicAfter = new CompilerDependencySnapshot([generatedPublicBRevision, generatedConsumer], [generatedEdge]);
		final generatedPublicComparison = CompilerDependencyInvalidator.compare(generatedPublicBefore, generatedPublicAfter);
		assertTrue(affected(generatedPublicComparison) == "GeneratedConsumer,GeneratedProvider",
			"a generated public signature change should continue through ordinary caller dependencies");
		final generatedConsumerReason = generatedPublicComparison.reasonFor("GeneratedConsumer");
		assertTrue(generatedConsumerReason != null
			&& generatedConsumerReason.describe().indexOf("generated-declarations-changed:GeneratedProvider") >= 0
			&& generatedConsumerReason.describe().indexOf("public-interface:GeneratedConsumer->GeneratedProvider") >= 0,
			"a propagated reason should retain both the macro-output cause and caller edge");
		final generatedAAgain = new CompilerDependencySnapshot([
			new CompilerTypedModuleRevision("GeneratedProvider", "public-same", "implementation-same", "source-same", null, null,
				CompilerConditionalCompilationObservation.empty(), generatedObservation("private-generated-a"))
		], []);
		assertTrue(generatedA.getCanonicalIdentity() == generatedAAgain.getCanonicalIdentity(),
			"returning to exact generated result A should reproduce its dependency snapshot");
		assertTrue(reasons(CompilerDependencyInvalidator.compare(generatedImplementationB, generatedAAgain)) == generatedReason,
			"generated-declaration A-to-B-to-A comparisons should reproduce deterministic privacy-safe reasons");

		final inlineA = snapshot(inlineSources("class Shared { public static inline function embedded():Int return 1; }"));
		final inlineB = snapshot(inlineSources("class Shared { public static inline function embedded():Int return 2; }"));
		final inlineComparison = CompilerDependencyInvalidator.compare(inlineA, inlineB);
		assertTrue(affected(inlineComparison) == "Left,Main,Shared",
			"an inline body edit should reach the inline call chain without invalidating the import-only sibling");
		final inlineMainReason = inlineComparison.reasonFor("Main");
		assertTrue(inlineMainReason != null
			&& inlineMainReason.describe().indexOf("inline-implementation:Left->Shared") >= 0
			&& inlineMainReason.describe().indexOf("inline-implementation:Main->Left") >= 0,
			"the inline reason should name both implementation-consuming edges");

		final constantA = snapshot(constantSources('class Api { public static final label:String = "A"; public static var mutable:Int = 1; }'));
		final constantB = snapshot(constantSources('class Api { public static final label:String = "B"; public static var mutable:Int = 1; }'));
		final constantComparison = CompilerDependencyInvalidator.compare(constantA, constantB);
		assertTrue(affected(constantComparison) == "Api,FieldReader,Main",
			"a constant value edit should reach function-body and field-initializer readers without invalidating import-only or mutable-field readers");
		final constantMainReason = constantComparison.reasonFor("Main");
		assertTrue(constantMainReason != null
			&& constantMainReason.describe().indexOf("constant-value:Main->Api:field:Api#static#label") >= 0,
			"the constant reader should name the exact implementation-consuming field edge");
		assertTrue(!constantComparison.isAffected("ImportOnly"), "an import alone should not claim that it embedded a constant value");
		assertTrue(!constantComparison.isAffected("MutableReader"), "an ordinary mutable field read should not claim an embedded constant value");
		final constantFieldReason = constantComparison.reasonFor("FieldReader");
		assertTrue(constantFieldReason != null
			&& constantFieldReason.describe().indexOf("constant-value:FieldReader->Api:field:Api#static#label") >= 0,
			"a field initializer should name the exact constant value that it embeds");
		final constantAAgain = snapshot(constantSources('class Api { public static final label:String = "A"; public static var mutable:Int = 1; }'));
		assertTrue(constantA.getCanonicalIdentity() == constantAAgain.getCanonicalIdentity(),
			"returning to the exact constant value should reproduce the original dependency snapshot");
		final constantReverse = CompilerDependencyInvalidator.compare(constantB, constantAAgain);
		assertTrue(affected(constantReverse) == affected(constantComparison) && reasons(constantReverse) == reasons(constantComparison),
			"constant A-to-B-to-A should reproduce affected modules and reason paths");
		final qualifiedConstantComparison = CompilerDependencyInvalidator.compare(snapshot(qualifiedConstantSources("A")),
			snapshot(qualifiedConstantSources("B")));
		assertTrue(affected(qualifiedConstantComparison) == "QualifiedFieldReader,QualifiedReader,pkg.Api",
			"a fully qualified constant edit should reach both function-body and field-initializer readers");
		final qualifiedReaderReason = qualifiedConstantComparison.reasonFor("QualifiedReader");
		assertTrue(qualifiedReaderReason != null
			&& qualifiedReaderReason.describe().indexOf("constant-value:QualifiedReader->pkg.Api:field:pkg.Api#static#label") >= 0,
			"the fully qualified reader should retain the exact selected field identity");

		final publicAAgain = snapshot(sharedSources(sharedA));
		assertTrue(publicA.getCanonicalIdentity() == publicAAgain.getCanonicalIdentity(),
			"rebuilding exact revision A after B should reproduce the original snapshot identity");
		final reverseComparison = CompilerDependencyInvalidator.compare(publicB, publicAAgain);
		assertTrue(affected(reverseComparison) == affected(publicComparison), "returning from B to A should predict the same affected modules");
		assertTrue(reasons(reverseComparison) == reasons(publicComparison), "returning from B to A should reproduce deterministic reason paths");

		final reorderedB = snapshot(sharedSources(sharedPublicB), true);
		assertTrue(publicB.getCanonicalIdentity() == reorderedB.getCanonicalIdentity(),
			"reordered typed-module input should not change the shared dependency snapshot");
		final reorderedComparison = CompilerDependencyInvalidator.compare(publicA, reorderedB);
		assertTrue(affected(publicComparison) == affected(reorderedComparison)
			&& reasons(publicComparison) == reasons(reorderedComparison),
			"module input order should not change affected modules or reason paths");

		Sys.println("COMPILER_DEPENDENCY_EDIT_SEQUENCE:PASS");
	}
}
