import sys.FileSystem;
import sys.io.File;

/** Array-backed Lambda operations, generic allocations and nullable returns retain native behavior. */
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
			'  static function copyGeneric<A>():Array<A> {',
			'    return new Array<A>();',
			'  }',
			'  static function nullableArray(flag:Bool, single:String):Null<Array<String>> {',
			'    return flag ? null : [single];',
			'  }',
			'  static function main():Void {',
			'    var values = f([3, 7]);',
			'    Sys.println(values.length);',
			'    Sys.println(values[0]);',
			'    Sys.println(values[1]);',
			'    var empty:Array<Int> = copyGeneric();',
			'    Sys.println(empty.length);',
			'    Sys.println(nullableArray(true, "ignored") == null);',
			'    Sys.println(nullableArray(false, "kept")[0]);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);

		var thrown:Dynamic = null;
		try {
			final expected = "2\n3\n7\n0\ntrue\nkept\n";
			M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", tmpRoot, "--run", "Main"], expected: expected});
			final typed = M14Stage3RuntimeFixture.typeMain({source: src, path: sourcePath, root: tmpRoot});
			final expanded = MacroStage.expandProgram([typed], []);
			final executable = EmitterStage.emitToDir(expanded, outDir);

			final lambdaMl = haxe.io.Path.join([outDir, 'Lambda.ml']);
			assertTrue(FileSystem.exists(lambdaMl), 'Expected Lambda.ml shim in emitted output.');
			final ocaml = File.getContent(lambdaMl);
			assertTrue(ocaml.indexOf('HxBootArray.to_list (Obj.magic it)') >= 0, 'Stage3 Lambda.list shim must accept array-backed bootstrap values.');
			assertTrue(ocaml.indexOf('Stdlib.List.fold_left') >= 0, 'Stage3 Lambda.fold shim must share the array-backed list conversion path.');
			assertTrue(ocaml.indexOf('Seq.t') < 0, 'Stage3 Lambda shim regression: array values were treated as Seq.t.');

			M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
			Sys.println("LAMBDA_ARRAY_SHIM:PASS");
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
