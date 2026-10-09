import sys.FileSystem;
import sys.io.File;

/**
	Checks that an array iterator in a static initializer survives OCaml emission.
	The program index supplies typed local identities for the initializer's closure,
	as it does in the native compiler's resolved-module typing path.
**/
class M14HihDynamicArrayIteratorRuntimeIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_hih_dynamic_array_iterator_runtime_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'class Main {',
			'  static var keep = (function() {',
			'    var d:Dynamic = [];',
			'    return d.iterator();',
			'  })();',
			'  static function main() {',
			'    Sys.println("ok");',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final resolved = new ResolvedModule("Main", mainHx, parsed);
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			final expanded = MacroStage.expandProgram([typed], []);
			final exePath = EmitterStage.emitToDir(expanded, outDir, true);
			assertTrue(FileSystem.exists(exePath), 'Emitter did not produce executable: ' + exePath);
			final code = Sys.command(exePath, []);
			assertTrue(code == 0, 'Executable failed for dynamic array iterator keepalive with exit code ' + code + '.');
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
