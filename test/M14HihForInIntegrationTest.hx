import sys.FileSystem;
import sys.io.File;

class M14HihForInIntegrationTest {
	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "' but got '" + actual + "'";
	}

	static function assertTrue(ok:Bool, label:String):Void {
		if (!ok)
			throw label;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) {
				deleteRecursive(haxe.io.Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function findLocalType(fn:TyFunctionEnv, name:String):String {
		for (l in fn.getLocals())
			if (l.getName() == name)
				return l.getType().getDisplay();
		for (p in fn.getParams())
			if (p.getName() == name)
				return p.getType().getDisplay();
		return "<missing>";
	}

	static function main() {
		final src = 'class Main {\n' + '  static function main() {\n' + '    var xs = ["A", "B"];\n' + '    for (x in xs) trace(x);\n'
			+ '    for (i in 0...3) trace(i);\n' + '  }\n' + '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final pm = new ParsedModule(src, decl, "<m14_hih_forin>");
		final tm = TyperStage.typeModule(pm);
		final cls = tm.getEnv().getMainClass();
		final fns = cls.getFunctions();

		var mainFn:Null<TyFunctionEnv> = null;
		for (f in fns)
			if (f.getName() == "main")
				mainFn = f;
		if (mainFn == null)
			throw "missing typed main()";

		assertEquals(findLocalType(mainFn, "xs"), "Array<String>", "xs array literal infers element type");
		assertEquals(findLocalType(mainFn, "x"), "String", "for-in over Array<String> binds String loop var");
		assertEquals(findLocalType(mainFn, "i"), "Int", "for-in over range binds Int loop var");

		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_hih_forin_runtime_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		final outDir = haxe.io.Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final runtimeMainPath = haxe.io.Path.join([srcDir, "Main.hx"]);
		final runtimeMain = [
			"class Main {",
			"  static function main() {",
			"    var sum = 0;",
			"    for (n in [1, 2, 3, 4]) {",
			"      sum += n;",
			"    }",
			'    Sys.println("sum=" + sum);',
			"  }",
			"}",
		].join("\n");
		File.saveContent(runtimeMainPath, runtimeMain);

		var thrown:Dynamic = null;
		try {
			final runtimeParsed = ParserStage.parse(runtimeMain, runtimeMainPath);
			final runtimeTyped = TyperStage.typeModule(runtimeParsed);
			final runtimeExpanded = MacroStage.expandProgram([runtimeTyped], []);
			final exePath = EmitterStage.emitToDir(runtimeExpanded, outDir, true);
			assertTrue(FileSystem.exists(exePath), "Emitter did not produce executable: " + exePath);

			final p = new sys.io.Process(exePath, []);
			final stdout = p.stdout.readAll().toString();
			final code = p.exitCode();
			p.close();
			assertTrue(code == 0, "Executable failed for for-in accumulator runtime check with exit code " + code + ".");
			assertTrue(stdout.indexOf("sum=10") >= 0, "Expected runtime output to contain sum=10, got:\n" + stdout);
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
