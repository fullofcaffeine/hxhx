import hxhx.BuildMetadataCollector;
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
		MacroState.reset();
	}
}
