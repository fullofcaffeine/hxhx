import sys.FileSystem;
import sys.io.File;

class M14Stage3ConcatArrayLengthIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_concat_array_length_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function f(a:Array<String>) {',
			'    return "5:" + a.length;',
			'  }',
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, sourcePath);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, false, false);

			final mainMl = haxe.io.Path.join([outDir, 'Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('HxRuntime.dynamic_toStdString (Obj.repr (HxBootArray.length (a)))') >= 0,
				'Stage3 string concat must stringify array length before OCaml ^.');
			assertTrue(ocaml.indexOf('^ (HxBootArray.length (a))') < 0, 'Stage3 string concat regression: array length was emitted as a raw int.');
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
