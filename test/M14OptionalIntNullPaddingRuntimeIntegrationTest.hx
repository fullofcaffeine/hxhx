import sys.FileSystem;
import sys.io.File;

/** Preserve nullable optional bounds through real String/Array declarations and native execution. */
class M14OptionalIntNullPaddingRuntimeIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_optional_int_null_padding_runtime_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function expect(cond:Bool, msg:String):Void {',
			'    if (!cond) throw msg;',
			'  }',
			'  static function main() {',
			'    var maybe:Null<Int> = null;',
			'    var s = "abcabc";',
			'    expect(s.indexOf("a", maybe) == 0, "indexOf nullable start mismatch");',
			'    expect(s.lastIndexOf("a", maybe) == 3, "lastIndexOf nullable start mismatch");',
			'    expect(s.substr(2, maybe) == "cabc", "substr nullable len mismatch");',
			'    expect(s.substring(2, maybe) == "cabc", "substring nullable end mismatch");',
			'    var arr = [1, 2, 1, 3];',
			'    expect(arr.indexOf(1, maybe) == 0, "array indexOf nullable from mismatch");',
			'    expect(arr.lastIndexOf(1, maybe) == 2, "array lastIndexOf nullable from mismatch");',
			'    var tail = arr.slice(2, maybe);',
			'    expect(tail.length == 2 && tail[0] == 1 && tail[1] == 3, "array slice nullable end mismatch");',
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
