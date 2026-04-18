import sys.FileSystem;
import sys.io.File;

class M14Stage3ReflectCompareMethodsShimIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_reflect_compare_methods_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function same(a:Void->Void, b:Void->Void) {',
			'    return Reflect.compareMethods(a, b);',
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

			final reflectMl = haxe.io.Path.join([outDir, 'Reflect.ml']);
			assertTrue(FileSystem.exists(reflectMl), 'Expected Reflect.ml shim in emitted output.');
			final ocaml = File.getContent(reflectMl);
			assertTrue(ocaml.indexOf('let compareMethods a b = HxReflect.same_closure (Obj.repr a) (Obj.repr b)') >= 0,
				'Stage3 Reflect shim must expose Reflect.compareMethods for upstream utest equality checks.');
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
