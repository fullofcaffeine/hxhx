import sys.FileSystem;
import sys.io.File;

class M14Stage3ImportAndRootTypeResolutionIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_import_and_root_type_resolution_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);
		FileSystem.createDirectory(haxe.io.Path.join([srcDir, 'utest']));

		final assertHx = haxe.io.Path.join([srcDir, 'utest', 'Assert.hx']);
		File.saveContent(assertHx, [
			'package utest;',
			'class Assert {',
			'  public static function contains(v:Dynamic, values:Dynamic, pos:Dynamic):Bool {',
			'    return true;',
			'  }',
			'}',
		].join("\n"));

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'package unit;',
			'import haxe.CallStack;',
			'import utest.Assert;',
			'class Main {',
			'  static function render():String {',
			'    return CallStack.toString([]);',
			'  }',
			'  static function check(c:Class<Dynamic>, n:String):Bool {',
			'    return Assert.contains(n, [], null) && Lambda.has(Type.getClassFields(c), n);',
			'  }',
			'  static function main() {',
			'    check(Main, "main");',
			'    render();',
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

			final mainMl = haxe.io.Path.join([outDir, 'Unit_Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Unit_Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('Haxe_CallStack.toString') >= 0 || ocaml.indexOf('CallStack.toString') >= 0,
				'Expected explicit short import to resolve to the imported `CallStack` provider.');
			assertTrue(ocaml.indexOf('Utest_Assert.contains') >= 0 || ocaml.indexOf('Assert.contains') >= 0,
				'Expected explicit imported short name `Assert` to resolve to the imported provider.');
			assertTrue(ocaml.indexOf('Lambda.has') >= 0, 'Expected root stdlib short name to remain `Lambda.has`.');
			assertTrue(ocaml.indexOf('Type.getClassFields') >= 0, 'Expected root stdlib short name to remain `Type.getClassFields`.');
			assertTrue(ocaml.indexOf('Unit_CallStack.') < 0, 'Found bad package-local qualification `Unit_CallStack`.');
			assertTrue(ocaml.indexOf('Unit_Assert.') < 0, 'Found bad package-local qualification `Unit_Assert`.');
			assertTrue(ocaml.indexOf('Unit_Lambda.') < 0, 'Found bad package-local qualification `Unit_Lambda`.');
			assertTrue(ocaml.indexOf('Unit_Type.') < 0, 'Found bad package-local qualification `Unit_Type`.');
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
