import backend.BackendContext;
import backend.cpp.CppTargetCore;

/**
	Exact projected Map type tests must reach a native runtime observer.
	Run the HXML for every contract. Set HXHX_CPP_MAP_CASE to erased, original, or
	families to diagnose one provider load. Unknown case names fail explicitly.
 */
class M14CppRuntimeTypeMapTest {
	static function main():Void {
		final requested = Sys.getEnv("HXHX_CPP_MAP_CASE");
		final cases = ["erased", "original", "families"];
		if (requested != null && !cases.contains(requested))
			throw "HXHX_CPP_MAP_CASE must select one of: " + cases.join(", ");
		final failures = new Array<String>();
		function check(name:String, label:String, action:Void->Void):Void {
			if (requested != null && requested != name)
				return;
			final started = haxe.Timer.stamp();
			Sys.println("CPP_RUNTIME_TYPE_MAP:START " + name);
			Sys.stdout().flush();
			try {
				action();
				Sys.println("CPP_RUNTIME_TYPE_MAP:PASS " + label + " seconds=" + (haxe.Timer.stamp() - started));
			} catch (error:haxe.Exception) {
				final message = label + ": " + error.message;
				failures.push(message);
				Sys.println("CPP_RUNTIME_TYPE_MAP:FAIL " + message);
			}
		}
		check("erased", "erased value rejects before publication", assertErasedValueRejected);
		check("original", "original generated-code and native contract", M14CppArrowMapLiteralContract.run);
		check("families", "cpp_map_runtime_type_seed", () -> {
			final name = "cpp_map_runtime_type_seed";
			final root = "test/oracle/" + name;
			final program = CppMapFixture.load(root + "/src/Main.hx");
			final result = CppTargetCore.emit(program,
				new BackendContext(".tmp/cpp-runtime-type-map/" + name, null, "Main", true, true, new haxe.ds.StringMap<String>()));
			if (!result.builtExecutable)
				throw "Map runtime type contract requires a native executable";
			final process = new sys.io.Process(result.entryPath, []);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
				throw "Map runtime type behavior differs for " + name + ": " + stdout + stderr;
		});
		if (failures.length > 0)
			throw failures.join("\n");
	}

	/** A valid Haxe operation remains explicitly unsupported until erased Map identity is preserved. */
	static function assertErasedValueRejected():Void {
		final program = CppMapFixture.load("test/oracle/cpp_map_runtime_type_seed/erased/Main.hx");
		final directory = ".tmp/cpp-map-erased-rejection-" + Date.now().getTime();
		sys.FileSystem.createDirectory(directory);
		final path = directory + "/existing.cpp";
		sys.io.File.saveContent(path, "previous-output\n");
		var diagnostic = "";
		try {
			CppTargetCore.emit(program, new BackendContext(directory, path, "Main", false, false, new haxe.ds.StringMap<String>()));
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic.indexOf("erased or unplanned Map test value") < 0)
			throw "C++ did not reject erased Map identity: " + diagnostic;
		if (sys.io.File.getContent(path) != "previous-output\n" || sys.FileSystem.readDirectory(directory).length != 1)
			throw "C++ changed output before rejecting erased Map identity";
		sys.FileSystem.deleteFile(path);
		sys.FileSystem.deleteDirectory(directory);
	}
}
