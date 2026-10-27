import sys.FileSystem;
import sys.io.File;

/** Nested enum patterns retain their selected declarations and bind payloads before use. */
class M14Stage3EnumExtractorBindingIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_enum_extractor_binding_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'enum Scope { Method(owner:String, name:String); Other; }',
			'enum Position { FilePos(line:Int, column:Int, offset:Int, scope:Scope); NoPos; }',
			'class Main {',
			'  static function f(item:Dynamic):Int {',
			'    return switch (item) {',
			'      case FilePos(_, _, _, s):',
			'        switch (s) {',
			'          case Method(_, _):',
			'            1;',
			'          default:',
			'            2;',
			'        }',
			'      default:',
			'        3;',
			'    }',
			'  }',
			'  static function main():Void {',
			'    Sys.println(f(FilePos(1, 2, 3, Method("Owner", "method"))));',
			'    Sys.println(f(FilePos(1, 2, 3, Other)));',
			'    Sys.println(f(NoPos));',
			'  }',
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);

		var thrown:Dynamic = null;
		try {
			final expected = "1\n2\n3\n";
			M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", tmpRoot, "--run", "Main"], expected: expected});
			final typed = M14Stage3RuntimeFixture.typeMain({source: src, path: sourcePath, root: tmpRoot});
			final expanded = MacroStage.expandProgram([typed], []);
			final executable = EmitterStage.emitToDir(expanded, outDir);
			M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
			Sys.println("ENUM_EXTRACTOR_BINDING:PASS");
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
