import sys.FileSystem;
import sys.io.File;

class M14HihLocalRestCallResolutionIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_hih_local_rest_call_resolution_" + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		final outDir = haxe.io.Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, "Main.hx"]);
		final src = [
			"class Main {",
			"  static function join(prefix:String, ...parts:String):String {",
			"    return prefix + \":\" + parts.toArray().join(\",\");",
			"  }",
			"  static function main() {",
			"    Sys.println(join(\"p\"));",
			"    Sys.println(join(\"p\", \"a\"));",
			"    Sys.println(join(\"p\", \"a\", \"b\"));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final mainMl = haxe.io.Path.join([outDir, "Main.ml"]);
			assertTrue(FileSystem.exists(mainMl), "Expected Main.ml output for local rest-call regression test.");
			final ocaml = File.getContent(mainMl);

			assertTrue(ocaml.indexOf('join ("p") (HxBootArray.create ())') >= 0, "Expected empty local rest call to pack into HxBootArray.create ().");
			assertTrue(ocaml.indexOf('join ("p") (HxBootArray.of_list ["a"])') >= 0, "Expected single local rest arg call to pack into HxBootArray.of_list.");
			assertTrue(ocaml.indexOf('join ("p") (HxBootArray.of_list ["a"; "b"])') >= 0,
				"Expected multi local rest arg call to pack all trailing args into HxBootArray.of_list.");
			assertTrue(ocaml.indexOf('join ("p") ("a")') < 0, "Found stale curried local rest-call emission for the single rest-arg case.");
			assertTrue(ocaml.indexOf('join ("p") ("a") ("b")') < 0, "Found stale curried local rest-call emission for the multi rest-arg case.");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}
}
