import sys.FileSystem;
import sys.io.File;

class M14Stage3DateToolsDurationStubIntegrationTest {
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

	static function assertContains(haystack:String, needle:String, message:String):Void {
		assertTrue(haystack.indexOf(needle) >= 0, message + "\nMissing: " + needle);
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		assertTrue(haystack.indexOf(needle) < 0, message + "\nUnexpected: " + needle);
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_datetools_duration_stub_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final mainPath = haxe.io.Path.join([tmpRoot, 'Main.hx']);
		final mainSrc = [
			'class Main {',
			'  public static var sinline:Float = DateTools.minutes(1);',
			'  public static function main():Void {}',
			'}',
		].join("\n");
		File.saveContent(mainPath, mainSrc);

		var thrown:Dynamic = null;
		try {
			final stdDateToolsPath = haxe.io.Path.normalize('vendor/haxe/std/DateTools.hx');
			final parsedMain = ParserStage.parse(mainSrc, mainPath);
			final parsedDateTools = ParserStage.parse(File.getContent(stdDateToolsPath), stdDateToolsPath);
			final typedMain = TyperStage.typeModule(parsedMain);
			final typedDateTools = TyperStage.typeModule(parsedDateTools);
			final expanded = MacroStage.expandProgram([typedMain, typedDateTools], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final dateToolsMl = haxe.io.Path.join([outDir, 'DateTools.ml']);
			assertTrue(FileSystem.exists(dateToolsMl), 'Expected DateTools.ml in emitted output.');
			final ocaml = File.getContent(dateToolsMl);
			assertContains(ocaml, 'let rec seconds (n : float) : float = ((n) *. (1000.))', 'Expected DateTools.seconds stub to use its parameter.');
			assertContains(ocaml, 'let rec minutes (n : float) : float = (((n) *. (60.)) *. (1000.))', 'Expected DateTools.minutes stub to use its parameter.');
			assertContains(ocaml, 'let rec hours (n : float) : float = ((((n) *. (60.)) *. (60.)) *. (1000.))',
				'Expected DateTools.hours stub to use its parameter.');
			assertContains(ocaml, 'let rec days (n : float) : float = (((((n) *. (24.)) *. (60.)) *. (60.)) *. (1000.))',
				'Expected DateTools.days stub to use its parameter.');
			assertNotContains(ocaml, 'let rec minutes (n : float) : float = (((((Obj.magic 0)) *. (60.))) *. (1000.))',
				'Expected DateTools.minutes not to emit poison arithmetic.');
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
