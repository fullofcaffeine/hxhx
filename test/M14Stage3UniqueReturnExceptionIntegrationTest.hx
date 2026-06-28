import sys.FileSystem;
import sys.io.File;

class M14Stage3UniqueReturnExceptionIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function countOccurrences(haystack:String, needle:String):Int {
		if (needle.length == 0)
			return 0;
		var count = 0;
		var offset = 0;
		while (true) {
			final found = haystack.indexOf(needle, offset);
			if (found < 0)
				break;
			count++;
			offset = found + needle.length;
		}
		return count;
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_unique_return_exception_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final pos = HxPos.unknown();
		final first = new HxFunctionDecl("moduleTest", Public, true, [], "String", [SReturn(EString("one"), pos)], "");
		final second = new HxFunctionDecl("moduleTest", Public, true, [], "String", [SReturn(EString("two"), pos)], "");
		final mainClass = new HxClassDecl("Main", false, [first, second], []);
		final decl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final parsed = new ParsedModule("", decl, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final expanded = MacroStage.expandProgram([typed], []);

		var thrown:Dynamic = null;
		try {
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final mainMl = haxe.io.Path.join([outDir, 'Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(countOccurrences(ocaml, 'exception HxReturn_moduleTest of Obj.t') == 1,
				'Expected the first duplicate return exception to keep the base name.');
			assertTrue(countOccurrences(ocaml, 'exception HxReturn_moduleTest_1 of Obj.t') == 1,
				'Expected the second duplicate return exception to receive a deterministic suffix.');
			assertTrue(ocaml.indexOf('with HxReturn_moduleTest v -> (Obj.magic v)') >= 0,
				'Expected the first function body to catch its base return exception.');
			assertTrue(ocaml.indexOf('with HxReturn_moduleTest_1 v -> (Obj.magic v)') >= 0,
				'Expected the second function body to catch its suffixed return exception.');
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println('debug_out=' + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}
}
