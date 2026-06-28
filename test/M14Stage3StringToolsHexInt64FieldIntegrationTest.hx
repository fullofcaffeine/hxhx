import sys.FileSystem;
import sys.io.File;

class M14Stage3StringToolsHexInt64FieldIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_stringtools_hex_int64_field_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final src = [
			'class Main {',
			'  static function toHex(v:haxe.Int64):String {',
			'    return "0x" + (v.high == 0 ? StringTools.hex(v.low) : StringTools.hex(v.high) + StringTools.hex(v.low, 8));',
			'  }',
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, sourcePath);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final mainMl = haxe.io.Path.join([outDir, 'Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('"high")) : int)') >= 0, 'Expected Int64.high anonymous field reads to be typed as int.');
			assertTrue(ocaml.indexOf('"low")) : int)') >= 0, 'Expected Int64.low anonymous field reads to be typed as int.');
			assertTrue(ocaml.indexOf('StringTools.hex (((Obj.magic (HxAnon.get (Obj.repr (v)) "low")) : int))') >= 0,
				'Expected StringTools.hex(v.low) to receive an int-typed field read.');
			assertTrue(ocaml.indexOf('StringTools.hex (((Obj.magic (HxAnon.get (Obj.repr (v)) "low")) : int)) (8)') >= 0,
				'Expected StringTools.hex(v.low, 8) to pass the digit count as int, not Obj.t.');
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
