import sys.FileSystem;
import sys.io.File;

class M14Stage3EnumExtractorBindingIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_enum_extractor_binding_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function f(item:Dynamic) {',
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
			assertTrue(ocaml.indexOf('let s = Obj.magic ((HxArray.get (Obj.magic __hx_sw_params_0) 3)) in') >= 0,
				'Stage3 enum extractor switch must bind constructor argument variables.');
			assertTrue(ocaml.indexOf('let __sw = (s)') >= 0,
				'Stage3 nested switch must use the constructor argument binding.');
			assertTrue(ocaml.indexOf('let __sw = (s)') > ocaml.indexOf('let s = Obj.magic'),
				'Stage3 nested switch referenced the constructor argument before binding it.');
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
