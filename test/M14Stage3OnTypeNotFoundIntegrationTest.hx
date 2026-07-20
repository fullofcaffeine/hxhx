import haxe.ds.StringMap;
import haxe.io.Path;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroRuntimeSession;
import hxhx.macro.MacroState;
import sys.io.File;

class M14Stage3OnTypeNotFoundIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
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
			final exe = MacroHostTestArtifact.resolve("test:m14:stage3-on-type-not-found");
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
