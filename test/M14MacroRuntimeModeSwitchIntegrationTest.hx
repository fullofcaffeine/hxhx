import haxe.io.Path;
import hxhx.ExprMacroExpander;
import hxhx.Stage3MacroHostSupport;
import hxhx.macro.MacroRuntimeMode;
import hxhx.macro.MacroState;
import sys.io.File;

class M14MacroRuntimeModeSwitchIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertEq(label:String, actual:String, expected:String):Void {
		if (actual == expected)
			return;
		fail(label + ': expected "' + expected + '" but got "' + actual + '"');
	}

	static function assertContains(label:String, actual:String, expected:String):Void {
		if (actual.indexOf(expected) >= 0)
			return;
		fail(label + ': expected "' + expected + '" in "' + actual + '"');
	}

	static function assertIntEq(label:String, actual:Int, expected:Int):Void {
		if (actual == expected)
			return;
		fail(label + ': expected ' + expected + ' but got ' + actual);
	}

	static function expectThrow(label:String, run:() -> Void, expected:String):Void {
		var caught = "";
		try {
			run();
		} catch (e:String) {
			caught = e;
		}
		if (caught.length == 0)
			fail(label + ": expected exception");
		assertContains(label + " message", caught, expected);
	}

	static function deleteRecursive(path:String):Void {
		if (!sys.FileSystem.exists(path))
			return;
		if (!sys.FileSystem.isDirectory(path)) {
			sys.FileSystem.deleteFile(path);
			return;
		}
		for (entry in sys.FileSystem.readDirectory(path))
			deleteRecursive(Path.join([path, entry]));
		sys.FileSystem.deleteDirectory(path);
	}

	static function main():Void {
		final plannedEntrypoints = Stage3MacroHostSupport.macroHostEntrypoints(["BuiltinMacros.smoke()", "demo.CliMacros.init()", "demo.CliMacros.init()"], [
			"unit.HelperMacros.getCompilationDate()",
			"HelperMacros.getCompilationDate()",
			"demo.ExprMacros.expand()"
		], true, ["nullSafety(\"demo\")", "demo.LibraryMacros.init()"]);
		assertEq("external macro host entrypoints", plannedEntrypoints.join(";"), "demo.LibraryMacros.init();demo.CliMacros.init();demo.ExprMacros.expand()");

		final fakeRepo = ".tmp/m14_stage3_macro_host_support";
		deleteRecursive(fakeRepo);
		sys.FileSystem.createDirectory(fakeRepo);
		sys.FileSystem.createDirectory(Path.join([fakeRepo, "scripts"]));
		sys.FileSystem.createDirectory(Path.join([fakeRepo, "scripts", "hxhx"]));
		final fakeBuildScript = Path.join([fakeRepo, "scripts", "hxhx", "build-hxhx-macro-host.sh"]);
		File.saveContent(fakeBuildScript, [
			"#!/usr/bin/env bash",
			"echo visible-build-context",
			"echo hidden-build-diagnostic >&2",
			"exit 7"
		].join("\n"));
		var buildError = "";
		try {
			Stage3MacroHostSupport.buildMacroHostExe(fakeRepo, [], []);
		} catch (e:String) {
			buildError = e;
		}
		assertContains("macro host build exit", buildError, "exit code 7");
		assertContains("macro host build stderr", buildError, "hidden-build-diagnostic");

		File.saveContent(fakeBuildScript, ["#!/usr/bin/env bash", "echo build-note >&2", "echo /tmp/fake-macro-host.exe"].join("\n"));
		assertEq("macro host executable path", Stage3MacroHostSupport.buildMacroHostExe(fakeRepo, [], []), "/tmp/fake-macro-host.exe");
		deleteRecursive(fakeRepo);

		Sys.putEnv("HXHX_MACRO_RUNTIME_MODE", null);
		assertEq("default mode", MacroRuntimeMode.resolve(null), MacroRuntimeMode.INPROC);

		Sys.putEnv("HXHX_MACRO_RUNTIME_MODE", MacroRuntimeMode.EXTERNAL_HOST);
		assertEq("env mode", MacroRuntimeMode.resolve(null), MacroRuntimeMode.EXTERNAL_HOST);
		assertEq("explicit mode", MacroRuntimeMode.resolve(MacroRuntimeMode.INPROC), MacroRuntimeMode.INPROC);
		expectThrow("invalid mode", () -> MacroRuntimeMode.resolve("weird"), "invalid macro runtime mode");

		Sys.putEnv("HXHX_MACRO_HOST_EXE", null);
		MacroState.reset();
		MacroState.seedFromCliDefines(["HXHX_FLAG=abc"]);
		MacroState.setGeneratedHxDir(".tmp/m14_macro_runtime_mode");

		final session = MacroRuntimeMode.openSession(MacroRuntimeMode.INPROC);
		final smoke = session.run("BuiltinMacros.smoke()");
		assertContains("smoke result", smoke, "smoke:type=builtin:String;define=yes");
		assertEq("smoke define", MacroState.definedValue("HXHX_SMOKE"), "1");

		final readFlag = session.run("BuiltinMacros.readFlag()");
		assertEq("read flag", readFlag, "flag=abc");

		final hookResult = session.run("BuiltinMacros.registerHooks()");
		assertEq("hook registration", hookResult, "hooks=ok");

		for (id in MacroState.listAfterTypingHookIds())
			session.runHook("afterTyping", id);
		for (id in MacroState.listOnGenerateHookIds())
			session.runHook("onGenerate", id);

		assertEq("afterTyping define", MacroState.definedValue("HXHX_AFTER_TYPING"), "1");
		assertEq("onGenerate define", MacroState.definedValue("HXHX_ON_GENERATE"), "1");
		assertContains("generated module name", MacroState.listOcamlModuleNames().join(","), "HxHxHook");

		session.close();

		MacroState.reset();
		MacroState.seedFromCliDefines(["HXHX_FLAG=ok"]);
		MacroState.setGeneratedHxDir(".tmp/m14_macro_runtime_generated_entrypoints");

		final generated = MacroRuntimeMode.openSession(MacroRuntimeMode.INPROC);
		assertEq("expr macro expansion", generated.expandExpr("hxhxmacros.ExprMacroShim.hello()"), "\"HELLO\"");
		final nestedReturnSource = [
			"class NestedReturnMacroArgument {",
			"  function run():String {",
			"    shouldFail(return hxhxmacros.ExprMacroShim.hello());",
			"  }",
			"}",
		].join("\n");
		final nestedReturnParsed = ParserStage.parse(nestedReturnSource, "NestedReturnMacroArgument.hx");
		final nestedReturnResolved = new ResolvedModule("NestedReturnMacroArgument", "NestedReturnMacroArgument.hx", nestedReturnParsed);
		final nestedReturnExpansion = ExprMacroExpander.expandResolvedModules([nestedReturnResolved], generated, ["hxhxmacros.ExprMacroShim.hello()"]);
		assertIntEq("nested return macro expansion count", nestedReturnExpansion.expandedCount, 1);
		final nestedReturnClass = HxModuleDecl.getMainClass(ResolvedModule.getParsed(nestedReturnExpansion.modules[0]).getDecl());
		switch (HxFunctionDecl.getBody(HxClassDecl.getFunctions(nestedReturnClass)[0])) {
			case [SExpr(ECall(EIdent("shouldFail"), [EReturn(EString("HELLO"))]), _)]:
			case body:
				fail("expression macro expansion lost the return wrapper around its expanded child: " + Std.string(body));
		}
		final nestedVariableSource = [
			"class NestedVariableMacroArgument {",
			"  function run():Void {",
			"    shouldFail(var value:String = hxhxmacros.ExprMacroShim.hello());",
			"  }",
			"}",
		].join("\n");
		final nestedVariableParsed = ParserStage.parse(nestedVariableSource, "NestedVariableMacroArgument.hx");
		final nestedVariableResolved = new ResolvedModule("NestedVariableMacroArgument", "NestedVariableMacroArgument.hx", nestedVariableParsed);
		final nestedVariableExpansion = ExprMacroExpander.expandResolvedModules([nestedVariableResolved], generated, ["hxhxmacros.ExprMacroShim.hello()"]);
		assertIntEq("nested variable initializer macro expansion count", nestedVariableExpansion.expandedCount, 1);
		final nestedVariableClass = HxModuleDecl.getMainClass(ResolvedModule.getParsed(nestedVariableExpansion.modules[0]).getDecl());
		switch (HxFunctionDecl.getBody(HxClassDecl.getFunctions(nestedVariableClass)[0])) {
			case [
				SExpr(ECall(EIdent("shouldFail"), [EVars([EVariableDeclaration(_, _, initializer, _, _, _)])]), _)
			]:
				switch (initializer) {
					case EString("HELLO"):
					case _:
						fail("expression macro expansion did not rewrite the declaration initializer");
				}
			case body:
				fail("expression macro expansion lost the declaration wrapper around its expanded child: " + Std.string(body));
		}
		final annotatedLocalSource = [
			"class AnnotatedLocalMacroInitializer {",
			"  function run():Void {",
			"    var @:example value:String = hxhxmacros.ExprMacroShim.hello();",
			"  }",
			"}",
		].join("\n");
		final annotatedLocalParsed = ParserStage.parse(annotatedLocalSource, "AnnotatedLocalMacroInitializer.hx");
		final annotatedLocalResolved = new ResolvedModule("AnnotatedLocalMacroInitializer", "AnnotatedLocalMacroInitializer.hx", annotatedLocalParsed);
		final annotatedLocalExpansion = ExprMacroExpander.expandResolvedModules([annotatedLocalResolved], generated, ["hxhxmacros.ExprMacroShim.hello()"]);
		assertIntEq("annotated local initializer macro expansion count", annotatedLocalExpansion.expandedCount, 1);
		final annotatedLocalClass = HxModuleDecl.getMainClass(ResolvedModule.getParsed(annotatedLocalExpansion.modules[0]).getDecl());
		switch (HxFunctionDecl.getBody(HxClassDecl.getFunctions(annotatedLocalClass)[0])) {
			case [SVar("value", "String", EString("HELLO"), _, metadata)]:
				assertEq("macro expansion must preserve local metadata", metadata == null ? "<missing>" : metadata.join("|"), "@:example");
			case body:
				fail("macro expansion changed the annotated local declaration: " + Std.string(body));
		}
		assertEq("args entrypoint", generated.run('hxhxmacros.ArgsMacros.setArg("ok")'), "ok");
		assertEq("arg define", MacroState.definedValue("HXHX_ARG"), "ok");
		assertEq("external entrypoint", generated.run("hxhxmacros.ExternalMacros.external()"), "external=ok");
		assertEq("external define", MacroState.definedValue("HXHX_EXTERNAL"), "1");
		assertContains("external module", MacroState.listOcamlModuleNames().join(","), "HxHxExternal");

		final onGenerateBefore = MacroState.listOnGenerateHookIds().length;
		assertEq("macro init", generated.run("Macro.init()"), "ok");
		assertIntEq("macro init onGenerate hook count", MacroState.listOnGenerateHookIds().length, onGenerateBefore + 1);

		assertEq("haxelib init", generated.run("hxhxmacros.HaxelibInitMacros.init()"), "ok");
		assertEq("haxelib define", MacroState.definedValue("HXHX_HAXELIB_INIT"), "1");

		Sys.putEnv("HXHX_PLUGIN_FIXTURE_CP", ".tmp/m14_macro_runtime_plugin_cp");
		assertEq("plugin init", generated.run("hxhxmacros.PluginFixtureMacros.init()"), "ok");
		assertEq("plugin define", MacroState.definedValue("HXHX_PLUGIN_FIXTURE"), "1");
		assertContains("plugin cp", MacroState.listClassPaths().join(","), ".tmp/m14_macro_runtime_plugin_cp");
		Sys.putEnv("HXHX_PLUGIN_FIXTURE_CP", null);

		for (id in MacroState.listAfterTypingHookIds())
			generated.runHook("afterTyping", id);
		for (id in MacroState.listOnGenerateHookIds())
			generated.runHook("onGenerate", id);
		for (id in MacroState.listAfterGenerateHookIds())
			generated.runHook("afterGenerate", id);

		assertEq("haxelib afterTyping define", MacroState.definedValue("HXHX_HAXELIB_INIT_AFTER_TYPING"), "1");
		assertEq("haxelib onGenerate define", MacroState.definedValue("HXHX_HAXELIB_INIT_ON_GENERATE"), "1");
		assertEq("haxelib afterGenerate define", MacroState.definedValue("HXHX_HAXELIB_INIT_AFTER_GENERATE"), "1");
		assertEq("plugin afterTyping define", MacroState.definedValue("HXHX_PLUGIN_FIXTURE_AFTER_TYPING"), "1");
		assertEq("plugin onGenerate define", MacroState.definedValue("HXHX_PLUGIN_FIXTURE_ON_GENERATE"), "1");
		final generatedModules = MacroState.listOcamlModuleNames().join(",");
		assertContains("haxelib generated module", generatedModules, "HxHxHaxelibInitGen");
		assertContains("plugin generated module", generatedModules, "HxHxPluginFixtureGen");

		MacroState.setDefine("HXHX_BUILD_MODULE", "Main");
		MacroState.clearBuildFields("Main");
		assertEq("build field macro", generated.run("hxhxmacros.BuildFieldMacros.addGeneratedField()"), "ok");
		final buildFields = MacroState.listBuildFields("Main");
		assertIntEq("build field count", buildFields.length, 1);
		assertContains("build field snippet", buildFields[0], "from_hxhx_build_macro");

		MacroState.clearBuildFields("Main");
		assertEq("return build field macro", generated.run("hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()"), "ok");
		final returnFields = MacroState.listBuildFields("Main");
		assertIntEq("return build field count", returnFields.length, 1);
		assertContains("return build field snippet", returnFields[0], "generated_return");
		assertContains("return build field trace", returnFields[0], "from_hxhx_build_macro_return");

		MacroState.clearBuildFields("Main");
		assertEq("replace build field macro", generated.run("hxhxmacros.ReturnFieldMacros.replaceGeneratedFieldReturn()"), "ok");
		final replaceFields = MacroState.listBuildFields("Main");
		assertIntEq("replace build field count", replaceFields.length, 1);
		assertContains("replace build field snippet", replaceFields[0], "generated_replace");
		assertContains("replace build field trace", replaceFields[0], "from_hxhx_build_macro_replaced");

		MacroState.clearBuildFields("Main");
		assertEq("field printer macro", generated.run("hxhxmacros.FieldPrinterMacros.addArgFunctionAndVar()"), "ok");
		final printedFields = MacroState.listBuildFields("Main");
		assertIntEq("field printer count", printedFields.length, 1);
		assertContains("field printer function", printedFields[0], "generated_with_args");
		assertContains("field printer var", printedFields[0], "generated_var = 123");
		assertContains("field printer trace", printedFields[0], "from_hxhx_field_printer");

		generated.close();
		Sys.putEnv("HXHX_MACRO_RUNTIME_MODE", null);
		Sys.println("OK m14 macro runtime mode switch");
	}
}
