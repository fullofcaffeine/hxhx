import sys.FileSystem;
import sys.io.File;

class M14HihQualifiedCallReceiverPaddingIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond) throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path)) return;
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_hih_qualified_call_receiver_padding_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'class Syntax {',
			'  public function new() {}',
			'  public function equal(left:Dynamic, right:Dynamic):Bool {',
			'    return true;',
			'  }',
			'}',
			'class Main {',
			'  public static function equal(left:Dynamic, right:Dynamic):Bool {',
			'    return Syntax.equal(left, right);',
			'  }',
			'  static function main() {',
			'    equal(1, 2);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			var foundPaddedCall = false;
			var foundUnpaddedCall = false;
			for (entry in FileSystem.readDirectory(outDir)) {
				if (!StringTools.endsWith(entry, '.ml')) continue;
				final mlPath = haxe.io.Path.join([outDir, entry]);
				final ocaml = File.getContent(mlPath);
				if (ocaml.indexOf('.equal ((Obj.magic HxRuntime.hx_null)) (left) (right)') >= 0) foundPaddedCall = true;
				if (ocaml.indexOf('.equal (left) (right)') >= 0) foundUnpaddedCall = true;
			}

			assertTrue(foundPaddedCall, 'Expected receiver-padded qualified call not found in emitted OCaml.');
			assertTrue(!foundUnpaddedCall, 'Found unpadded qualified call shape `.equal (left) (right)` in emitted OCaml.');
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
