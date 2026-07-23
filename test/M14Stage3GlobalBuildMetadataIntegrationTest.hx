import hxhx.BuildMetadataCollector;
import hxhx.Stage3BuildMacroSupport;
import hxhx.macro.MacroState;

class M14Stage3GlobalBuildMetadataIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(label:String, values:Array<String>, expected:String):Void {
		if (values.indexOf(expected) >= 0)
			return;
		throw label + ': expected "' + expected + '" in [' + values.join(", ") + ']';
	}

	static function assertNotContains(label:String, values:Array<String>, unexpected:String):Void {
		if (values.indexOf(unexpected) < 0)
			return;
		throw label + ': did not expect "' + unexpected + '" in [' + values.join(", ") + ']';
	}

	static function generatedReturnType(module:ResolvedModule, functionName:String):String {
		final declaration = ResolvedModule.getParsed(module).getDecl();
		for (fn in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(declaration)))
			if (HxFunctionDecl.getName(fn) == functionName)
				return HxFunctionDecl.getReturnTypeHint(fn);
		return "<missing>";
	}

	static function main():Void {
		final source = [
			"@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())",
			"class Target {",
			"}"
		].join("\n");

		MacroState.reset();
		MacroState.registerGlobalMetadata("", "@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())", true, true, false);
		MacroState.registerGlobalMetadata("demo.Target", "@:autoBuild(hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn())", false, true, false);
		MacroState.registerGlobalMetadata("demo.pkg", '@:build(hxhxmacros.ArgsMacros.setArg("pkg"))', true, true, false);
		MacroState.registerGlobalMetadata("demo.Target", "@:build(hxhxmacros.ArgsMacros.setArg(\"field-only\"))", false, false, true);
		MacroState.registerGlobalMetadata("demo.Target", "@:demoMeta", false, true, true);

		final targetExprs = BuildMetadataCollector.collectBuildMacroExprs(source, "demo.Target");
		assertTrue(targetExprs.length == 2, "expected deduped source+global build exprs for exact target");
		assertContains("exact target source/global build", targetExprs, "hxhxmacros.BuildFieldMacros.addGeneratedField()");
		assertContains("exact target autoBuild", targetExprs, "hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()");
		assertNotContains("exact target field-only rule", targetExprs, 'hxhxmacros.ArgsMacros.setArg("field-only")');
		assertNotContains("exact target non-build metadata", targetExprs, "@:demoMeta");

		final recursiveExprs = BuildMetadataCollector.collectBuildMacroExprs("class Other {}", "demo.pkg.Inner");
		assertTrue(recursiveExprs.length == 2, "expected root recursive rule plus package-recursive rule");
		assertContains("recursive package root rule", recursiveExprs, "hxhxmacros.BuildFieldMacros.addGeneratedField()");
		assertContains("recursive package match", recursiveExprs, 'hxhxmacros.ArgsMacros.setArg("pkg")');
		assertNotContains("recursive package exact rule", recursiveExprs, "hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()");

		final unrelatedExprs = BuildMetadataCollector.collectBuildMacroExprs("class Other {}", "elsewhere.Main");
		assertTrue(unrelatedExprs.length == 1, "expected only root recursive build rule for unrelated module");
		assertContains("unrelated module root rule", unrelatedExprs, "hxhxmacros.BuildFieldMacros.addGeneratedField()");
		assertNotContains("unrelated module package rule", unrelatedExprs, 'hxhxmacros.ArgsMacros.setArg("pkg")');

		final parsed = ParserStage.parse(source, "Target.hx");
		final resolved = new ResolvedModule("Target", "Target.hx", parsed);
		final generatedIntText = "public static function generated_answer():Int return 42;";
		final generatedStringText = 'public static function generated_answer():String return "private-generated-value";';
		final generatedInt = Stage3BuildMacroSupport.applyGeneratedMembers(resolved, [generatedIntText]);
		final generatedString = Stage3BuildMacroSupport.applyGeneratedMembers(resolved, [generatedStringText]);
		assertTrue(generatedReturnType(generatedInt, "generated_answer") == "Int", "generated Int member should be merged before typing");
		assertTrue(generatedReturnType(generatedString, "generated_answer") == "String", "generated String member should be merged before typing");
		final intObservation = ResolvedModule.getGeneratedDeclarations(generatedInt);
		final stringObservation = ResolvedModule.getGeneratedDeclarations(generatedString);
		assertTrue(intObservation.getCanonicalIdentity() != stringObservation.getCanonicalIdentity(),
			"different generated declarations should have different observations");
		assertTrue(intObservation.getCanonicalIdentity().indexOf(generatedIntText) < 0
			&& stringObservation.getCanonicalIdentity().indexOf("private-generated-value") < 0,
			"generated-declaration observations must not retain raw member text");
		final index = TyperIndex.build([generatedInt]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index);
		loader.markResolvedAlready([generatedInt]);
		final typed = TyperStage.typeResolvedModule(generatedInt, index, loader, true);
		assertTrue(typed.getGeneratedDeclarations().getCanonicalIdentity() == intObservation.getCanonicalIdentity(),
			"typing should preserve the exact generated-declaration observation");
		MacroState.reset();
	}
}
