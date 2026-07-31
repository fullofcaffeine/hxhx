import backend.BackendContext;
import backend.vm.NekoTargetCore;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that the Neko backend consumes the strict typed-local projection.

	The fixture reuses one source name for an outer Int and an inner String. Neko
	must emit distinct target locals and preserve the inner-then-outer runtime
	result without recovering identity from the source spelling.
**/
class M14NekoTypedLocalProjectionIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "`)";
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
			"  static function revise(value:String):String {",
			"    value = value + \"!\";",
			"    return value;",
			"  }",
			"  static function main() {",
			"    var value:Int = 1;",
			"    {",
			"      var value:String = \"inner\";",
			"      Sys.println(revise(value));",
			"    }",
			"    Sys.println(value);",
			"  }",
			"}"
		].join("\n");
		return MacroStage.expandProgram([TyperStage.typeModule(ParserStage.parse(source, "Main.hx"))], []);
	}

	static function assertReadableCollisionAvoidance():Void {
		final firstValue = new TyLocalBinding(TyLocalId.forSourceDeclaration("Main.main#projection-fixture", 0, Variable, "value"), "value",
			TyType.fromHintText("Int"), Variable);
		final reservedSuffix = new TyLocalBinding(TyLocalId.forSourceDeclaration("Main.main#projection-fixture", 1, Variable, "value_1"), "value_1",
			TyType.fromHintText("String"), Variable);
		final shadowValue = new TyLocalBinding(TyLocalId.forSourceDeclaration("Main.main#projection-fixture", 2, Variable, "value"), "value",
			TyType.fromHintText("String"), Variable);
		final catalog = new TypedBackendLocalCatalog([shadowValue, reservedSuffix, firstValue]);
		assertTrue(catalog.projectedName(firstValue) == "value", "first local should retain its readable source name");
		assertTrue(catalog.projectedName(reservedSuffix) == "value_1", "an existing suffixed source name should remain available to its own binding");
		assertTrue(catalog.projectedName(shadowValue) == "value_2", "shadowed local should skip a suffix already used by source");
	}

	static function runNeko(path:String):String {
		final process = new sys.io.Process("neko", [path]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		assertTrue(code == 0, "generated Neko bytecode failed with exit " + code + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function main():Void {
		assertReadableCollisionAvoidance();
		final tmpRoot = Path.normalize(".tmp/m14_neko_typed_local_projection_" + Std.string(Date.now().getTime()));
		final sourceOnlyDir = Path.join([tmpRoot, "source"]);
		final sourceOnlyOutput = Path.join([sourceOnlyDir, "main.n"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(sourceOnlyDir);
		var failure:Null<String> = null;
		try {
			final sourceDefines = new StringMap<String>();
			sourceDefines.set(NekoTargetCore.SOURCE_ONLY_DEFINE, "1");
			NekoTargetCore.emit(program(), new BackendContext(sourceOnlyDir, sourceOnlyOutput, "Main", true, false, sourceDefines));
			final source = File.getContent(Path.join([sourceOnlyDir, "main.neko"]));
			assertContains(source, "var value = 1;", "outer typed binding should keep a readable Neko local name");
			assertContains(source, 'var value_1 = "inner";', "shadowed typed binding should receive a distinct Neko local name");
			assertContains(source, "function(value)", "function parameter should use its strict projected transport name");
			assertContains(source, '(value = (value + "!"));', "parameter write and read should use the same projected binding");
			assertContains(source, "Main_revise(value_1)", "inner read should select the projected String binding");
			assertContains(source, "$" + 'print(value, "\\n");', "outer read should select the projected Int binding");

			if (commandAvailable("nekoc") && commandAvailable("neko")) {
				final runtimeDir = Path.join([tmpRoot, "runtime"]);
				FileSystem.createDirectory(runtimeDir);
				final runtimeOutput = Path.join([runtimeDir, "main.n"]);
				NekoTargetCore.emit(program(), new BackendContext(runtimeDir, runtimeOutput, "Main", true, false, new StringMap<String>()));
				assertTrue(runNeko(runtimeOutput) == "inner!\n1", "generated Neko program did not preserve inner then outer shadowing behavior");
			}
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
