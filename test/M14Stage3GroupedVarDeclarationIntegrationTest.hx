import sys.FileSystem;
import sys.io.File;

class M14Stage3GroupedVarDeclarationIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
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

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_grouped_var_declaration_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'package unit;',
			'import haxe.Int64.*;',
			'class Main {',
			'  static function touch():Void {',
			'    var a:Int64, b:Int64;',
			'    a = Int64.make(0, 1);',
			'    b = Int64.make(0, 2);',
			'    a = Int64.mul(a, b);',
			'    b = Int64.add(a, b);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final mainMl = haxe.io.Path.join([outDir, 'Unit_Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Unit_Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('let a = ref') >= 0, 'Expected grouped declaration to emit `a` as a mutable local ref.');
			assertTrue(ocaml.indexOf('let b = ref') >= 0, 'Expected grouped declaration to emit `b` as a mutable local ref.');
			assertTrue(ocaml.indexOf('(b := __hx_v; ())') >= 0, 'Expected later assignments to lower through mutable `b`.');
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
