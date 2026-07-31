import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that Lua String lowering consumes exact typed-local projections.

	The fixture reuses `value` for an outer Int, an inner String, and a helper
	parameter. Only the exact String bindings may select Lua String helpers, and
	a failed output write must not affect a later render.
**/
class M14LuaTypedLocalProjectionIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw message + " (unexpected `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function commandAvailable(command:String):Bool
		return Sys.command("sh", ["-c", "command -v " + command + " >/dev/null 2>&1"]) == 0;

	static function program():MacroExpandedProgram {
		final source = [
			"class Main {",
			"  static function upper(value:String):String {",
			"    return (value + \"!\").toUpperCase();",
			"  }",
			"  static function main() {",
			"    var value:Int = 7;",
			"    {",
			"      var value:String = \"inner\";",
			"      Sys.println(upper(value));",
			"      Sys.println(value.toUpperCase());",
			"    }",
			"    Sys.println(value);",
			"  }",
			"}"
		].join("\n");
		return MacroStage.expandProgram([TyperStage.typeModule(ParserStage.parse(source, "Main.hx"))], []);
	}

	static function emit(outputDir:String, outputPath:String):String {
		if (!FileSystem.exists(outputDir))
			FileSystem.createDirectory(outputDir);
		BackendRegistry.requireForTarget("lua-native")
			.emit(program(), new BackendContext(outputDir, outputPath, "Main", true, false, new StringMap<String>()));
		return File.getContent(outputPath);
	}

	static function runLua(path:String):String {
		final process = new sys.io.Process("lua", [path]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		assertTrue(code == 0, "generated Lua failed with exit " + code + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_lua_typed_local_projection_" + Std.string(Date.now().getTime()));
		final directDir = Path.join([tmpRoot, "direct"]);
		final directPath = Path.join([directDir, "Main.lua"]);
		final repeatedDir = Path.join([tmpRoot, "repeated"]);
		final repeatedPath = Path.join([repeatedDir, "Main.lua"]);
		final afterFailureDir = Path.join([tmpRoot, "after-failure"]);
		final afterFailurePath = Path.join([afterFailureDir, "Main.lua"]);
		deleteRecursive(tmpRoot);

		var failure:Null<String> = null;
		try {
			final direct = emit(directDir, directPath);
			final repeated = emit(repeatedDir, repeatedPath);
			assertTrue(direct == repeated, "equivalent Lua requests produced different strict-projection output");
			assertContains(direct, "local value = 7", "outer Int binding should keep its readable projected name");
			assertContains(direct, 'local value_1 = "inner"', "inner String binding should receive a distinct projected name");
			assertContains(direct, "upper = function(value)", "helper parameters should use their own exact function catalog");
			assertContains(direct, 'return __hxhx_string_to_upper_case((tostring(value) .. tostring("!")))',
				"helper String concatenation and method calls should lower from the exact parameter type");
			assertContains(direct, "print(__hxhx_string_to_upper_case(value_1))", "inner String binding should select the Lua String helper");
			assertNotContains(direct, "print(__hxhx_string_to_upper_case(value))", "outer Int binding must not borrow the shadowed String binding's type");

			final blockedPath = Path.join([tmpRoot, "blocked.lua"]);
			FileSystem.createDirectory(blockedPath);
			var failedWrite = false;
			try {
				emit(tmpRoot, blockedPath);
			} catch (_:Dynamic) {
				failedWrite = true;
			}
			assertTrue(failedWrite, "fixture output-path failure did not occur");

			final afterFailure = emit(afterFailureDir, afterFailurePath);
			assertTrue(afterFailure == direct, "a failed Lua request changed the next strict-projection output");
			if (commandAvailable("lua"))
				assertTrue(runLua(afterFailurePath) == "INNER!\nINNER\n7", "generated Lua did not preserve helper, inner String, then outer Int behavior");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
