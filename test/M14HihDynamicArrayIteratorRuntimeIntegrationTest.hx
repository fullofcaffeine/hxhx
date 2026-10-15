import sys.FileSystem;
import sys.io.File;

/**
	Checks that an array iterator in a static initializer survives OCaml emission.
	The production declaration loader supplies Array identity and typed locals for
	the initializer's closure before the ordinary OCaml emitter receives it.
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
			M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", srcDir, "--run", "Main"], expected: "ok\n"});
			final typed = M14Stage3RuntimeFixture.typeMain({source: src, path: mainHx, root: srcDir});
			final expanded = MacroStage.expandProgram([typed], []);
			final exePath = EmitterStage.emitToDir(expanded, outDir, true);
			assertTrue(FileSystem.exists(exePath), 'Emitter did not produce executable: ' + exePath);
			M14Stage3RuntimeFixture.observe({command: exePath, arguments: [], expected: "ok\n"});
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
