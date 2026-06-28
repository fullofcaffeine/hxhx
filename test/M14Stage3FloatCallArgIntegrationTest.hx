import sys.FileSystem;
import sys.io.File;

class M14Stage3FloatCallArgIntegrationTest {
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_float_call_arg_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		final stdOutDir = haxe.io.Path.join([tmpRoot, 'std_out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final dateToolsPath = haxe.io.Path.join([tmpRoot, 'DateTools.hx']);
		final mainPath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final dateToolsSrc = [
			'class DateTools {',
			'  public static function minutes(value:Float):Float {',
			'    return value * 60.0 * 1000.0;',
			'  }',
			'}',
		].join("\n");
		final mainSrc = [
			'class Main {',
			'  public static var sinline:Float = DateTools.minutes(1);',
			'  public static function wrap(value:Int):Float {',
			'    return DateTools.minutes(value);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(dateToolsPath, dateToolsSrc);
		File.saveContent(mainPath, mainSrc);

		var thrown:Dynamic = null;
		try {
			final parsedDateTools = ParserStage.parse(dateToolsSrc, dateToolsPath);
			final parsedMain = ParserStage.parse(mainSrc, mainPath);
			final typed = [TyperStage.typeModule(parsedDateTools), TyperStage.typeModule(parsedMain)];
			final expanded = MacroStage.expandProgram(typed, []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final mainMl = haxe.io.Path.join([outDir, 'Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('DateTools.minutes (float_of_int 1)') >= 0,
				'Expected Int literal argument to DateTools.minutes(Float) to be coerced to float.');
			assertTrue(ocaml.indexOf('DateTools.minutes (float_of_int value)') >= 0,
				'Expected Int local argument to DateTools.minutes(Float) to be coerced to float.');
			assertTrue(ocaml.indexOf('DateTools.minutes (1)') < 0, 'Expected DateTools.minutes(1) not to emit an int argument.');

			final upstreamLikeSrc = [
				'package unit;',
				'class MyClass {',
				'  static public inline var sinline = DateTools.minutes(1);',
				'}',
			].join("\n");
			final upstreamLikePath = haxe.io.Path.normalize('vendor/haxe/tests/unit/src/unit/MyClass.hx');
			final stdDateToolsPath = haxe.io.Path.normalize('vendor/haxe/std/DateTools.hx');
			final parsedUpstreamLike = ParserStage.parse(upstreamLikeSrc, upstreamLikePath);
			final parsedStdDateTools = ParserStage.parse(File.getContent(stdDateToolsPath), stdDateToolsPath);
			final typedUpstreamLike = TyperStage.typeModule(parsedUpstreamLike);
			final typedStdDateTools = TyperStage.typeModule(parsedStdDateTools);
			final expandedUpstreamLike = MacroStage.expandProgram([typedStdDateTools, typedUpstreamLike], []);
			EmitterStage.emitToDir(expandedUpstreamLike, stdOutDir, true, false);
			final upstreamLikeMl = haxe.io.Path.join([stdOutDir, 'Unit_MyClass.ml']);
			assertTrue(FileSystem.exists(upstreamLikeMl), 'Expected Unit_MyClass.ml in emitted upstream-like output.');
			final upstreamLikeOcaml = File.getContent(upstreamLikeMl);
			assertTrue(upstreamLikeOcaml.indexOf('DateTools.minutes (float_of_int 1)') >= 0,
				'Expected std DateTools.minutes(Float) resolver fallback to coerce Int literal arguments.');
			assertTrue(upstreamLikeOcaml.indexOf('DateTools.minutes (1)') < 0, 'Expected std DateTools.minutes(1) not to emit an int argument.');
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
