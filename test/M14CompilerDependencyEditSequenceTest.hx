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

	static function snapshot(sources:Array<DependencyEditSource>, reverseModules:Bool = false):CompilerDependencySnapshot {
		final resolved = [
			for (source in sources)
				new ResolvedModule(source.modulePath, source.filePath, ParserStage.parse(source.source, source.filePath))
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

	static function affected(comparison:CompilerDependencyComparison):String
		return [for (invalidation in comparison.getInvalidations()) invalidation.modulePath].join(",");

	static function reasons(comparison:CompilerDependencyComparison):String
		return [for (invalidation in comparison.getInvalidations()) invalidation.describe()].join("\n");

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
