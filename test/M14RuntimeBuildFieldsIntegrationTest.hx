import haxe.io.Path;
import hxhx.macro.BuildFieldSnapshotPayload;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
import sys.io.File;

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
			final exe = MacroHostTestArtifact.resolve("test:m14:runtime-build-fields");
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
