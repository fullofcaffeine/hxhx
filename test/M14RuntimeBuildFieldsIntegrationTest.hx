import haxe.io.Path;
import hxhx.macro.BuildFieldSnapshotPayload;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
import sys.io.File;
import sys.io.Process;

class M14RuntimeBuildFieldsIntegrationTest {
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

	static function lastNonEmptyLine(text:String):String {
		if (text == null)
			return "";
		final lines = text.split("\n");
		var i = lines.length - 1;
		while (i >= 0) {
			final trimmed = StringTools.trim(lines[i]);
			if (trimmed.length > 0)
				return trimmed;
			i -= 1;
		}
		return "";
	}

	static function buildMacroHost(entrypoint:String):String {
		final command = [
			'HXHX_MACRO_HOST_FORCE_STAGE0=1',
			'HXHX_MACRO_HOST_ENTRYPOINTS=\'' + entrypoint + '\'',
			'HXHX_MACRO_HOST_EXTRA_CP=\'test/fixtures/hxhx-macros/src\'',
			'bash scripts/hxhx/build-hxhx-macro-host.sh 2>&1'
		].join(" ");
		final result = runShell(command);
		if (result.code != 0)
			fail("macro host build failed: " + result.stdout + result.stderr);
		final exe = lastNonEmptyLine(result.stdout);
		if (exe.length == 0)
			fail("macro host build produced no executable path: " + result.stdout);
		return exe;
	}

	static function main():Void {
		final originalHostExe = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		final fixturePath = Path.normalize("test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeBuildFieldCarrier.hx");
		final source = File.getContent(fixturePath);
		final parsed = new ParsedModule(source, new HxParser(source).parseModule("RuntimeBuildFieldCarrier"), fixturePath);
		MacroState.reset();
		MacroState.setCurrentPos({file: fixturePath, min: 0, max: source.length});
		MacroState.setBuildFieldsPayload(BuildFieldSnapshotPayload.encodeParsedModule(parsed));

		var failure:Null<String> = null;
		try {
			final exe = buildMacroHost("hxhxmacros.RuntimeContextApiMacros.probeBuildFieldsSnapshot()");
			Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);
			final output = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeBuildFieldsSnapshot()");
			assertContains("build fields output", output, "buildFields=");
			assertContains("build fields output", output, "answer=:fieldMeta");
			assertContains("build fields output", output, "routeTag=:propMeta");
			assertContains("build fields output", output, "render=:funMeta");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_BUILD_FIELDS").indexOf("answer=:fieldMeta") >= 0, "expected build fields define");
		} catch (e:String) {
			failure = e;
		} catch (e:haxe.Exception) {
			failure = e.message;
		}

		Sys.putEnv("HXHX_MACRO_HOST_EXE", originalHostExe);
		MacroState.reset();

		if (failure != null)
			fail(failure);
	}
}
