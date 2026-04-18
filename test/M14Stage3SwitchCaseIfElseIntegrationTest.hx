import sys.FileSystem;
import sys.io.File;

class M14Stage3SwitchCaseIfElseIntegrationTest {
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

	static function assertParserKeepsElseBranch():Void {
		final expr = HxParser.parseExprText('switch (e) { case "u": var t = d.getDay(); if (t == 0) "7" else Std.string(t); }');
		final ok = switch (expr) {
			case ESwitch(_, _, [ECall(ELambda(["t"], ETernary(_, EString("7"), ECall(EField(EIdent("Std"), "string"), [EIdent("t")]))), _)]):
				true;
			case _:
				false;
		}
		assertTrue(ok, 'Parser dropped the expression-if else branch inside a switch case.');
	}

	static function main():Void {
		assertParserKeepsElseBranch();

		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_switch_case_if_else_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'DateTools.hx']);
		final src = [
			'class DateTools {',
			'  static function __format_get(d:Dynamic, e:String):String {',
			'    return switch (e) {',
			'      case "u":',
			'        var t = d.getDay();',
			'        if (t == 0) "7" else Std.string(t);',
			'      default:',
			'        "";',
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

			final mlPath = haxe.io.Path.join([outDir, 'DateTools.ml']);
			assertTrue(FileSystem.exists(mlPath), 'Expected DateTools.ml in emitted output.');
			final ocaml = File.getContent(mlPath);
			assertTrue(ocaml.indexOf('Std.string') >= 0, 'Stage3 switch case if/else regression: else Std.string branch was not emitted.');
			assertTrue(ocaml.indexOf('else (HxRuntime.hx_null)') < 0,
				'Stage3 switch case if/else regression: else branch was lowered as null.');
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
