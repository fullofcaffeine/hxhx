import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that a same-class instance call keeps exactly one receiver when its
	final optional position argument is omitted.

	The typed call can already contain an explicit `this` argument. Stage3 must
	reuse that receiver, append only the omitted optional argument, and emit an
	OCaml call whose arity matches the instance method definition.
**/
class M14Stage3OptionalInstanceReceiverIntegrationTest {
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
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_stage3_optional_instance_receiver"]);
		final sourceDir = Path.join([root, "src"]);
		final sourcePath = Path.join([sourceDir, "Main.hx"]);
		final outDir = Path.join([root, "out"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceDir);

		final source = [
			"class Main {",
			"  public function new() {}",
			"  static function numericCast(value:Int):Int return value;",
			"  function deq(expected:Dynamic, actual:Dynamic, ?pos:haxe.PosInfos):Void {",
			"    Sys.println(\"numeric-cast-arity-ok\");",
			"  }",
			"  function test():Void {",
			"    deq(0, numericCast(0));",
			"  }",
			"  static function main():Void {",
			"    new Main().test();",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);

		var thrown:Dynamic = null;
		try {
			final baseline = commandOutput("haxe", ["-cp", sourceDir, "--run", "Main"]);
			assertTrue(baseline.code == 0, "Haxe 4.3.7 rejected the focused optional-instance-call program: " + baseline.stderr);
			assertTrue(baseline.stdout == "numeric-cast-arity-ok\n", "unexpected Haxe 4.3.7 optional-instance-call output:\n" + baseline.stdout);

			final parsed = ParserStage.parse(source, sourcePath);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			final executable = EmitterStage.emitToDir(expanded, outDir, true);
			final generated = File.getContent(Path.join([outDir, "Main.ml"]));
			assertTrue(generated.indexOf("deq (this_) (this_)") < 0,
				"Stage3 emitted the already-forwarded instance receiver twice when an optional argument was omitted");
			assertTrue(generated.indexOf("deq (this_) (Obj.repr (0)) (Obj.repr (numericCast (0))) ((Obj.magic HxRuntime.hx_null))") >= 0,
				"Stage3 did not preserve one receiver and append only the omitted optional position argument");

			final executed = commandOutput(executable);
			assertTrue(executed.code == 0, "focused optional-instance-call executable failed: " + executed.stderr);
			assertTrue(executed.stdout == baseline.stdout, "Stage3 optional-instance-call output differs from Haxe 4.3.7:\n" + executed.stdout);
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
