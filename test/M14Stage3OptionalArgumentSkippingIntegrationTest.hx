import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Proves that Stage3 preserves Haxe 4.3.7 type-directed optional-argument skipping. **/
class M14Stage3OptionalArgumentSkippingIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function commandOutput(command:String, ?arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments == null ? [] : arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_stage3_optional_argument_skipping"]);
		final sourceDir = Path.join([root, "src"]);
		final sourcePath = Path.join([sourceDir, "Main.hx"]);
		final outDir = Path.join([root, "out"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceDir);

		final source = [
			"class Main {",
			"  static function install(account:String, repository:String, ?branch:String, ?sourcePath:String, useRetry:Bool = false, ?alternateName:String):Void {",
			"    Sys.println(useRetry ? \"retry\" : \"noretry\");",
			"  }",
			"  static function main():Void {",
			"    install(\"HaxeFoundation\", \"hxjava\", true);",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);

		var thrown:Dynamic = null;
		try {
			final baseline = commandOutput("haxe", ["-cp", sourceDir, "--run", "Main"]);
			assertTrue(baseline.code == 0, "Haxe 4.3.7 rejected the optional-skipping fixture: " + baseline.stderr);
			assertTrue(baseline.stdout == "retry\n", "unexpected Haxe 4.3.7 optional-skipping output: " + baseline.stdout);

			final parsed = ParserStage.parse(source, sourcePath);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			final executable = EmitterStage.emitToDir(expanded, outDir, true);
			final generated = File.getContent(Path.join([outDir, "Main.ml"]));
			final callStart = generated.indexOf("install (\"HaxeFoundation\") (\"hxjava\")");
			assertTrue(callStart >= 0, "Stage3 did not emit the focused install call");
			final callEnd = generated.indexOf("\n", callStart);
			final call = generated.substring(callStart, callEnd < 0 ? generated.length : callEnd);
			final firstNull = call.indexOf("HxRuntime.hx_null");
			final secondNull = firstNull < 0 ? -1 : call.indexOf("HxRuntime.hx_null", firstNull + 1);
			final boolArg = call.indexOf("(true)");
			final trailingNull = boolArg < 0 ? -1 : call.indexOf("HxRuntime.hx_null", boolArg + 1);
			assertTrue(firstNull >= 0 && secondNull > firstNull && boolArg > secondNull && trailingNull > boolArg,
				"Stage3 did not place the Bool argument after the two skipped String positions: " + call);

			final executed = commandOutput(executable);
			assertTrue(executed.code == 0, "Stage3 optional-skipping executable failed: " + executed.stderr);
			assertTrue(executed.stdout == baseline.stdout, "Stage3 optional-skipping output differs from Haxe 4.3.7: " + executed.stdout);
		} catch (error:Dynamic) {
			thrown = error;
		}

		if (thrown != null) {
			Sys.println("debug_out=" + root);
			throw thrown;
		}
		deleteRecursive(root);
	}
}
