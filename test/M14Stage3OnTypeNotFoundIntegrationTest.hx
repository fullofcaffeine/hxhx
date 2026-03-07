import haxe.ds.StringMap;
import haxe.io.Path;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroRuntimeSession;
import hxhx.macro.MacroState;
import sys.io.File;
import sys.io.Process;

class M14Stage3OnTypeNotFoundIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
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

	static function buildMacroHost(entrypoints:Array<String>):String {
		final command = [
			'HXHX_MACRO_HOST_FORCE_STAGE0=1',
			'HXHX_MACRO_HOST_ENTRYPOINTS=\'${entrypoints.join(";")}\'',
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
		final originalHostExe = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		final tmpRoot = ".tmp/m14_stage3_on_type_not_found";
		final generatedDir = Path.join([tmpRoot, "_gen_hx"]);
		deleteRecursive(tmpRoot);
		sys.FileSystem.createDirectory(tmpRoot);

		MacroState.reset();
		MacroState.setCurrentPos({file: "M14Stage3OnTypeNotFoundIntegrationTest.hx", min: 0, max: 0});
		MacroState.setGeneratedHxDir(generatedDir);

		var session:Null<MacroRuntimeSession> = null;
		var failure:Null<String> = null;
		try {
			final exe = buildMacroHost(["hxhxmacros.RuntimeContextApiMacros.registerOnTypeNotFoundDefineType()"]);
			Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);
			session = MacroHostClient.openSession();

			session.run("hxhxmacros.RuntimeContextApiMacros.registerOnTypeNotFoundDefineType()");

			final hooks = MacroState.listOnTypeNotFoundHookIds();
			assertTrue(hooks.length == 1, "expected exactly one registered onTypeNotFound hook");

			final loader = new ModuleLoader([generatedDir], new StringMap<String>(), new TyperIndex(), function(typePath:String):Bool {
				for (hookId in hooks)
					if (session.runTypeNotFoundHook(hookId, typePath))
						return true;
				return false;
			});

			final info = loader.ensureTypeAvailable("generated.runtime.RuntimeMissingType", "", []);
			assertTrue(info != null, "expected generated runtime type to resolve after onTypeNotFound");
			assertTrue(info.getFullName() == "generated.runtime.RuntimeMissingType", "expected full type name to match generated type");

			final generatedPath = Path.join([generatedDir, "generated", "runtime", "RuntimeMissingType.hx"]);
			assertTrue(sys.FileSystem.exists(generatedPath), "expected generated type file at " + generatedPath);
			final generatedSource = File.getContent(generatedPath);
			assertTrue(generatedSource.indexOf("class RuntimeMissingType") >= 0, "expected generated source for RuntimeMissingType");

			final emitted = MacroState.listGeneratedHxModuleNames();
			assertTrue(emitted.indexOf("generated.runtime.RuntimeMissingType") >= 0, "expected generated hx ledger to contain RuntimeMissingType");
		} catch (e:String) {
			failure = e;
		} catch (e:haxe.Exception) {
			failure = e.message;
		}

		if (session != null)
			session.close();
		Sys.putEnv("HXHX_MACRO_HOST_EXE", originalHostExe);
		MacroState.reset();
		deleteRecursive(tmpRoot);

		if (failure != null)
			fail(failure);
	}
}
