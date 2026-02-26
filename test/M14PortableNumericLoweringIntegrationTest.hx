import backend.BackendContext;
import backend.ocaml.OcamlTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14PortableNumericLoweringIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) {
				deleteRecursive(Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function findMainModulePath(outDir:String):String {
		var fallback:Null<String> = null;
		for (entry in FileSystem.readDirectory(outDir)) {
			if (entry == "Main.ml" || entry == "main.ml") {
				return Path.join([outDir, entry]);
			}
			if (StringTools.endsWith(entry, "Main.ml")) {
				final candidate = Path.join([outDir, entry]);
				if (!StringTools.endsWith(entry, "_Main.ml") && !StringTools.endsWith(entry, "__Main.ml")) {
					return candidate;
				}
				if (fallback == null)
					fallback = candidate;
			}
		}
		if (fallback != null)
			return fallback;
		throw "unable to locate emitted main module in " + outDir;
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_portable_numeric_lowering_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final source = [
			"class Main {",
			"  static function id(v:Int):Int {",
			"    return v;",
			"  }",
			"  static function main() {",
			"    var base:Int = 7;",
			"    var sum:Int = base + id(2);",
			"    var prod:Int = base * id(3);",
			"    var rem:Int = base % id(5);",
			"    Sys.println(\"num=\" + Std.string(sum) + \",\" + Std.string(prod) + \",\" + Std.string(rem));",
			"  }",
			"}"
		].join("\n");

		var failure:Null<String> = null;
		try {
			final parsed = ParserStage.parse(source, "PortableNumericMain.hx");
			final typed = TyperStage.typeModule(parsed);
			final program = MacroStage.expandProgram([typed], []);
			final context = new BackendContext(outDir, null, "Main", true, true, HxDefineMap.fromRawDefines(["ocaml_profile=portable"]));
			final result = new OcamlTargetCore().emit(program, context);
			final exePath = result.entryPath;
			assertTrue(FileSystem.exists(exePath), "OcamlTargetCore did not produce executable: " + exePath);

			final mainMlPath = findMainModulePath(outDir);
			final mainMl = File.getContent(mainMlPath);
			assertTrue(mainMl.indexOf("let sum = (Obj.magic 0)") < 0, "portable numeric lowering should avoid poison fallback for Int + call result");
			assertTrue(mainMl.indexOf("let prod = (Obj.magic 0)") < 0, "portable numeric lowering should avoid poison fallback for Int * call result");
			assertTrue(mainMl.indexOf("let rem = (Obj.magic 0)") < 0, "portable numeric lowering should avoid poison fallback for Int % call result");
			assertContains(mainMl, " + ", "portable numeric lowering should emit integer addition for Int + call");
			assertContains(mainMl, " * ", "portable numeric lowering should emit integer multiplication for Int * call");
			assertContains(mainMl, " mod ", "portable numeric lowering should emit integer modulo for Int % call");

			final process = new sys.io.Process(exePath, []);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final exitCode = process.exitCode();
			process.close();
			assertTrue(exitCode == 0, "portable numeric lowering executable failed with exit code " + exitCode + ". stderr=\n" + stderr);
			assertContains(stdout, "num=9,21,2", "portable numeric lowering runtime output should preserve int numeric behavior");
		} catch (e:haxe.Exception) {
			failure = e.message;
		} catch (msg:String) {
			failure = msg;
		}

		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
