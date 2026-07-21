import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds and executes the repo-owned `Int64 + Int` behavior contract through
	the native Stage3 OCaml emitter.

	The shared typer first selects the exact private `haxe.Int64.addInt`
	declaration. This test then proves that Stage3 preserves the selected call's
	real operands, supplies the corresponding OCaml helper, and retains signed
	64-bit wraparound when the generated program runs.
**/
class M14Stage3Int64AddIntIntegrationTest {
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

	static function commandOutput(command:String):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final sourcePath = "test/oracle/cpp_int64_add_int_seed/src/Main.hx";
		final source = HxConditionalCompilation.filterSource(File.getContent(sourcePath), new StringMap<String>());
		final int64Source = [
			"package haxe;",
			"@:transitive abstract Int64(Int) from Int to Int {",
			"  public static function ofInt(value:Int):Int64 return cast value;",
			"  public static function make(high:Int, low:Int):Int64 return cast low;",
			"  public static function toStr(value:Int64):String return '';",
			"  public static function add(left:Int64, right:Int64):Int64 return left;",
			"  @:op(A + B) @:commutative private static inline function addInt(value:Int64, amount:Int):Int64 return value;",
			"}",
		].join("\n");
		final int64Resolved = new ResolvedModule("haxe.Int64", "haxe/Int64.hx", ParserStage.parse(int64Source, "haxe/Int64.hx"));
		final mainResolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(source, sourcePath));
		final resolved = [int64Resolved, mainResolved];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final provisional = TyperStage.typeResolvedModule(mainResolved, index, loader, true);
		final typed = TypedAbstractOperatorLowering.lowerModules([provisional], index)[0];
		final program = new MacroExpandedProgram([typed], false);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_stage3_int64_add_int"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);

		var thrown:Dynamic = null;
		try {
			final executable = EmitterStage.emitToDir(program, root, true);
			final generatedMain = File.getContent(Path.join([root, "Main.ml"]));
			final generatedHelper = File.getContent(Path.join([root, "Haxe_Int64.ml"]));
			assertTrue(generatedMain.indexOf("Haxe_Int64.addInt") >= 0, "Stage3 did not preserve the exact haxe.Int64.addInt call selected by shared typing.");
			assertTrue(generatedMain.indexOf("Haxe_Int64.addInt ((Obj.magic 0))") < 0,
				"Stage3 replaced a selected addInt operand with bring-up poison instead of reading the typed temporary.");
			assertTrue(generatedHelper.indexOf("let addInt") >= 0, "Stage3 emitted a call to haxe.Int64.addInt without supplying its OCaml implementation.");
			assertTrue(generatedHelper.indexOf("Obj.magic") < 0, "The Int64 helper must not use Obj.magic to hide an incompatible representation.");

			final executed = commandOutput(executable);
			assertTrue(executed.code == 0, "focused Stage3 Int64 + Int executable failed: " + executed.stderr);
			final expected = File.getContent("test/oracle/cpp_int64_add_int_seed/expected.stdout");
			assertTrue(executed.stdout == expected, "unexpected focused Stage3 Int64 + Int stdout:\n" + executed.stdout);
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
