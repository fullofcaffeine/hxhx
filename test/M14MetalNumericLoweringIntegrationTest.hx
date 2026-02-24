import backend.BackendContext;
import backend.ocaml.OcamlTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14MetalNumericLoweringIntegrationTest {
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
		final tmpRoot = Path.normalize(".tmp/m14_metal_numeric_lowering_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final source = [
			"class Main {",
			"  static function main() {",
			"    var base:Int = 7;",
			"    var arr = [1, 2, 3, 4];",
			"    var q:Float = base / arr.length;",
			"    var r:Int = base % arr.length;",
			"    var mixed:Float = q + 0.5;",
			"    Sys.println(\"num=\" + Std.string(q) + \",\" + Std.string(r) + \",\" + Std.string(mixed));",
			"  }",
			"}"
		].join("\n");

		var failure:Null<String> = null;
		try {
			final parsed = ParserStage.parse(source, "MetalNumericMain.hx");
			final typed = TyperStage.typeModule(parsed);
			final program = MacroStage.expandProgram([typed], []);
			final context = new BackendContext(outDir, null, "Main", true, true, HxDefineMap.fromRawDefines(["ocaml_profile=metal"]));
			final result = new OcamlTargetCore().emit(program, context);
			final exePath = result.entryPath;
			assertTrue(FileSystem.exists(exePath), "OcamlTargetCore did not produce executable: " + exePath);

			final mainMlPath = findMainModulePath(outDir);
			final mainMl = File.getContent(mainMlPath);
			assertTrue(mainMl.indexOf("let q = (Obj.magic 0)") < 0, "metal numeric lowering should avoid poison fallback for division result");
			assertTrue(mainMl.indexOf("let r = (Obj.magic 0)") < 0, "metal numeric lowering should avoid poison fallback for modulo result");
			assertTrue(mainMl.indexOf("let mixed = (Obj.magic 0)") < 0, "metal numeric lowering should avoid poison fallback for mixed arithmetic result");
			assertContains(mainMl, "/.", "metal numeric lowering should emit float division for Int/length combinations");
			assertContains(mainMl, " mod ", "metal numeric lowering should emit int modulo for Int/length combinations");
			assertContains(mainMl, "+.", "metal numeric lowering should emit float addition for mixed Int/Float combinations");

			final process = new sys.io.Process(exePath, []);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final exitCode = process.exitCode();
			process.close();
			assertTrue(exitCode == 0, "metal numeric lowering executable failed with exit code " + exitCode + ". stderr=\n" + stderr);
			assertContains(stdout, "num=1.75,3,2.25", "metal numeric lowering runtime output should preserve mixed numeric behavior");
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
