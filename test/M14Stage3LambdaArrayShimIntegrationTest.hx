import sys.FileSystem;
import sys.io.File;

class M14Stage3LambdaArrayShimIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_lambda_array_shim_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function f(a:Array<Int>) {',
			'    var l = Lambda.list(a);',
			'    var b = Lambda.array(a);',
			'    return b;',
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

			final lambdaMl = haxe.io.Path.join([outDir, 'Lambda.ml']);
			assertTrue(FileSystem.exists(lambdaMl), 'Expected Lambda.ml shim in emitted output.');
			final ocaml = File.getContent(lambdaMl);
			assertTrue(ocaml.indexOf('HxBootArray.to_list (Obj.magic it)') >= 0,
				'Stage3 Lambda.list shim must accept array-backed bootstrap values.');
			assertTrue(ocaml.indexOf('Stdlib.List.fold_left') >= 0,
				'Stage3 Lambda.fold shim must share the array-backed list conversion path.');
			assertTrue(ocaml.indexOf('Seq.t') < 0,
				'Stage3 Lambda shim regression: array values were treated as Seq.t.');
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
