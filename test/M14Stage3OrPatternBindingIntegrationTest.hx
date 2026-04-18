import sys.FileSystem;
import sys.io.File;

class M14Stage3OrPatternBindingIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_or_pattern_binding_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function f(item:Dynamic) {',
			'    return switch (item) {',
			'      case A(s) | B(s):',
			'        s;',
			'      default:',
			'        "not_found";',
			'    }',
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
			assertTrue(ocaml.indexOf('let s = Obj.magic ((HxArray.get (Obj.magic __hx_sw_params_0) 0)) in') >= 0,
				'Stage3 OR-pattern switch must bind shared constructor argument variables.');
			assertTrue(ocaml.indexOf('Obj.magic (s)') > ocaml.indexOf('let s = Obj.magic'),
				'Stage3 OR-pattern switch referenced the shared binding before declaring it.');
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
