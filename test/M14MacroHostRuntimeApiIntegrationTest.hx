import haxe.io.Path;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
import sys.io.Process;

class M14MacroHostRuntimeApiIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function assertContains(label:String, actual:String, expected:String):Void {
		if (actual.indexOf(expected) >= 0)
			return;
		fail(label + ': expected "' + expected + '" in "' + actual + '"');
	}

	static function runShell(command:String):{code:Int, stdout:String, stderr:String} {
		final process = new Process("sh", ["-lc", command]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function buildMacroHostWithProbe():String {
		final exprs = [
			"hxhxmacros.RuntimeContextApiMacros.probeConfigAndPosition()",
			"hxhxmacros.RuntimeContextApiMacros.probeBuiltinTypePlumbing()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalContextSnapshot()",
			"hxhxmacros.RuntimeContextApiMacros.probeCallArguments()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalImports()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalUsing()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalTVars()",
			"hxhxmacros.RuntimeContextApiMacros.probeModuleLookup()",
			"hxhxmacros.RuntimeContextApiMacros.probeTypedExprPlumbing()",
			"hxhxmacros.RuntimeContextApiMacros.probeCompilerInclude()",
			"hxhxmacros.RuntimeContextApiMacros.probeResources()",
			"hxhxmacros.RuntimeContextApiMacros.probeMessages()",
			"hxhxmacros.RuntimeContextApiMacros.probeParse()",
			"hxhxmacros.RuntimeContextApiMacros.probeMakeExprAndSignature()"
		];
		final command = [
			'HXHX_MACRO_HOST_FORCE_STAGE0=1',
			'HXHX_MACRO_HOST_ENTRYPOINTS=\'${exprs.join(";")}\'',
			'HXHX_MACRO_HOST_EXTRA_CP=\'test/fixtures/hxhx-macros/src\'',
			'bash scripts/hxhx/build-hxhx-macro-host.sh | tail -n 1'
		].join(" ");
		final result = runShell(command);
		if (result.code != 0)
			fail("macro host build failed: " + result.stderr);
		final exe = StringTools.trim(result.stdout);
		if (exe.length == 0)
			fail("macro host build produced no executable path");
		return exe;
	}

	static function main():Void {
		final originalHostExe = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		MacroState.reset();
		MacroState.seedFromCliDefines(["reflaxe-target=ocaml", "target.name=ocaml"]);
		MacroState.seedCompilerConfiguration(["--ocaml", "-main", "Main", "--no-output"], ["/virtual/haxe/std"], "ocaml");
		MacroState.addClassPath("test/fixtures/hxhx-macros/src");
		MacroState.setCurrentPos({
			file: Path.normalize("test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx"),
			min: 12,
			max: 34
		});
		MacroState.setLocalContext({
			modulePath: "hxhxmacros.RuntimeContextApiMacros",
			methodName: "probeLocalContextSnapshot",
			localTypeText: "String",
			expectedTypeText: "Bool",
			callArgumentExprTexts: ["1", "2 + 3", "{ ok: true }"],
			localTVars: [
				{
					name: "count",
					typeText: "Int",
					id: 1,
					capture: false,
					isStatic: false
				},
				{
					name: "label",
					typeText: "String",
					id: 2,
					capture: true,
					isStatic: false
				}
			]
		});

		var failure = "";
		try {
			final exe = buildMacroHostWithProbe();
			Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);

			final output = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeConfigAndPosition()");
			assertContains("probe version", output, "cfg.version=40307");
			assertContains("probe args", output, "args=4");
			assertContains("probe std", output, "std=1");
			assertContains("probe unicode", output, "unicode=1");
			assertContains("probe classpath", output, "cp=");
			assertContains("probe display", output, "display=None");
			assertContains("probe file", output, "file=test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_ARGS") == "4", "expected runtime args define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_FILE") == "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx",
				"expected runtime file define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_MODE") == "None", "expected runtime display mode define");
			assertTrue(Std.parseInt(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_CP")) > 0, "expected runtime classpath define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_RESOLVED").indexOf("RuntimeContextApiMacros.hx") >= 0,
				"expected resolved fixture path define");

			final typeOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeBuiltinTypePlumbing()");
			assertContains("type probe getType", typeOutput, "getType=String");
			assertContains("type probe resolveType", typeOutput, "resolveType=Bool");
			assertContains("type probe nullType", typeOutput, "nullType=Null<String>");
			assertContains("type probe typeof", typeOutput, "typeof=Int");
			assertContains("type probe follow", typeOutput, "follow=Null<String>");
			assertContains("type probe unify", typeOutput, "unify=1");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_BOOL") == "Bool", "expected runtime bool type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_NULL") == "Null<String>", "expected runtime null type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_LITERAL") == "Int", "expected runtime literal type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_FOLLOW") == "Null<String>", "expected runtime follow define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_UNIFY") == "1", "expected runtime unify define");

			final localContextOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalContextSnapshot()");
			assertContains("local context module", localContextOutput, "module=hxhxmacros.RuntimeContextApiMacros");
			assertContains("local context method", localContextOutput, "method=probeLocalContextSnapshot");
			assertContains("local context local type", localContextOutput, "localType=String");
			assertContains("local context expected type", localContextOutput, "expectedType=Bool");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_LOCAL_MODULE") == "hxhxmacros.RuntimeContextApiMacros", "expected local module define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_LOCAL_METHOD") == "probeLocalContextSnapshot", "expected local method define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_LOCAL_TYPE") == "String", "expected local type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_EXPECTED_TYPE") == "Bool", "expected expected type define");

			final callArgumentsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeCallArguments()");
			assertContains("call arguments summary", callArgumentsOutput, "callArgs=1;(2+3);{ok:true}");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CALL_ARGUMENTS") == "1;(2+3);{ok:true}", "expected call arguments define");

			final localImportsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalImports()");
			assertContains("local imports String", localImportsOutput, "INormal:String");
			assertContains("local imports Template alias", localImportsOutput, "IAsName(T):haxe.Template");
			assertContains("local imports wildcard", localImportsOutput, "IAll:haxe.macro");
			assertContains("local imports define", MacroState.definedValue("HXHX_RUNTIME_LOCAL_IMPORTS"), "IAsName(T):haxe.Template");

			final localUsingOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalUsing()");
			assertContains("local using StringTools", localUsingOutput, "StringTools");
			assertContains("local using Path", localUsingOutput, "haxe.io.Path");
			assertContains("local using define", MacroState.definedValue("HXHX_RUNTIME_LOCAL_USING"), "haxe.io.Path");

			final localTVarsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalTVars()");
			assertContains("local tvars count", localTVarsOutput, "count:Int:1:plain");
			assertContains("local tvars label", localTVarsOutput, "label:String:2:capture");
			assertContains("local tvars define", MacroState.definedValue("HXHX_RUNTIME_LOCAL_TVARS"), "label:String:2:capture");

			final moduleOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeModuleLookup()");
			assertContains("module lookup output", moduleOutput, "moduleLookup=hxhxmacros.RuntimeContextApiMacros");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_MODULE_LOOKUP") == "hxhxmacros.RuntimeContextApiMacros", "expected module lookup define");

			final typedExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeTypedExprPlumbing()");
			assertContains("typed expr output", typedExprOutput, "typedExpr=");
			assertContains("typed expr type", typedExprOutput, "typedType=Int");
			assertTrue(Std.parseInt(MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_VISITS")) > 0, "expected typed expr visits define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR").indexOf("+") >= 0, "expected typed expr string define");

			final includeOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeCompilerInclude()");
			assertContains("include output", includeOutput, "include=hxhxmacros.RuntimeContextApiMacros");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_INCLUDE") == "hxhxmacros.RuntimeContextApiMacros", "expected runtime include define");
			assertTrue(MacroState.listIncludedModules().indexOf("hxhxmacros.RuntimeContextApiMacros") >= 0, "expected included module snapshot");

			final resourceOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeResources()");
			assertContains("resource output", resourceOutput, "resource=resource=ok");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_RESOURCE") == "resource=ok", "expected runtime resource define");

			final messagesOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeMessages()");
			assertContains("messages output warning", messagesOutput, "warning:runtime-warning@");
			assertContains("messages output info", messagesOutput, "info:runtime-info@");
			assertContains("messages define", MacroState.definedValue("HXHX_RUNTIME_MESSAGES"), "info:runtime-info@");

			final parseOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeParse()");
			assertContains("parse output", parseOutput, "parse=call+inline");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_PARSE") == "call+inline", "expected runtime parse define");

			final makeExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeMakeExprAndSignature()");
			assertContains("makeExpr output", makeExprOutput, "makeExpr=object;signature=");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_MAKE_EXPR") == "object", "expected runtime makeExpr define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_SIGNATURE").length == 32, "expected runtime signature define");
		} catch (e:String) {
			failure = e;
		} catch (e:haxe.Exception) {
			failure = e.message;
		}

		Sys.putEnv("HXHX_MACRO_HOST_EXE", originalHostExe);
		MacroState.clearCurrentPos();
		MacroState.clearLocalContext();

		if (failure.length > 0)
			fail(failure);
		Sys.println("OK m14 macro host runtime api");
	}
}
