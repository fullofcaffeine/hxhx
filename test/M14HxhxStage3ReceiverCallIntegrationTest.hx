import sys.FileSystem;
import sys.io.File;

class M14HxhxStage3ReceiverCallIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_hxhx_stage3_receiver_call_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'class Main {',
			'  public function new() {}',
			'  function add(v:Int):Int {',
			'    return v + 1;',
			'  }',
			'  function callOn(other:Main, n:Int):Int {',
			'    return other.add(n);',
			'  }',
			'  static function main() {',
			'    var m = new Main();',
			'    Sys.println(Std.string(m.callOn(m, 41)));',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			final exePath = EmitterStage.emitToDir(expanded, outDir, true);
			assertTrue(FileSystem.exists(exePath), 'Emitter did not produce executable: ' + exePath);

			var mainMl:Null<String> = null;
			for (entry in FileSystem.readDirectory(outDir)) {
				if (entry == 'Main.ml' || entry == 'main.ml' || StringTools.endsWith(entry, '__Main.ml')) {
					mainMl = haxe.io.Path.join([outDir, entry]);
					break;
				}
			}
			if (mainMl == null) {
				throw 'Stage3 output missing main module (`Main.ml` or `*__Main.ml`); outDir entries: '
					+ FileSystem.readDirectory(outDir).join(',');
			}

			final ocaml = File.getContent(mainMl);
			assertTrue(
				ocaml.indexOf('add (other) (n)') >= 0,
				'Stage3 receiver-call emit missing `add (other) (n)` call shape.'
			);
			assertTrue(
				ocaml.indexOf('add (this_) (other) (n)') < 0,
				'Stage3 receiver-call regression: emitted over-applied `add (this_) (other) (n)`.'
			);
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
