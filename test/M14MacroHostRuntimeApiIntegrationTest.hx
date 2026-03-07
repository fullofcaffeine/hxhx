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
			"hxhxmacros.RuntimeContextApiMacros.probeBuiltinTypePlumbing()"
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
		MacroState.setCurrentPos({
			file: Path.normalize("test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx"),
			min: 12,
			max: 34
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
			assertContains("probe display", output, "display=None");
			assertContains("probe file", output, "file=test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_ARGS") == "4", "expected runtime args define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_FILE") == "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx",
				"expected runtime file define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_MODE") == "None", "expected runtime display mode define");

			final typeOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeBuiltinTypePlumbing()");
			assertContains("type probe getType", typeOutput, "getType=String");
			assertContains("type probe resolveType", typeOutput, "resolveType=Bool");
			assertContains("type probe nullType", typeOutput, "nullType=Null<String>");
			assertContains("type probe typeof", typeOutput, "typeof=Int");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_BOOL") == "Bool", "expected runtime bool type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_NULL") == "Null<String>", "expected runtime null type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_LITERAL") == "Int", "expected runtime literal type define");
		} catch (e:String) {
			failure = e;
		} catch (e:haxe.Exception) {
			failure = e.message;
		}

		Sys.putEnv("HXHX_MACRO_HOST_EXE", originalHostExe);
		MacroState.clearCurrentPos();

		if (failure.length > 0)
			fail(failure);
		Sys.println("OK m14 macro host runtime api");
	}
}
