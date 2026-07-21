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
	64-bit wraparound when the generated program runs. A second executable proves
	that ordinary Haxe `Int` values are converted to the OCaml Int64 carrier when
	they are assigned to an `Int64` local, while an existing Int64 value is not
	converted twice.
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

	static function typedProgram(source:String, sourcePath:String, int64Source:String):MacroExpandedProgram {
		final int64Resolved = new ResolvedModule("haxe.Int64", "haxe/Int64.hx", ParserStage.parse(int64Source, "haxe/Int64.hx"));
		final mainResolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(source, sourcePath));
		final resolved = [int64Resolved, mainResolved];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final provisional = TyperStage.typeResolvedModule(mainResolved, index, loader, true);
		final typed = TypedAbstractOperatorLowering.lowerModules([provisional], index)[0];
		return new MacroExpandedProgram([typed], false);
	}

	static function main():Void {
		final typedTemporaryArguments = @:privateAccess EmitterStage.stage3TypedLambdaArgumentTypes("(haxe.Int64, Int)->Dynamic", 2);
		assertTrue(typedTemporaryArguments != null && typedTemporaryArguments.length == 2,
			"Stage3 did not recover the concrete parameter types carried by a typed temporary function.");
		assertTrue(typedTemporaryArguments[0].toString() == "haxe.Int64" && typedTemporaryArguments[1].toString() == "Int",
			"Stage3 changed the declared types of a typed temporary function.");
		assertTrue(@:privateAccess EmitterStage.stage3TypedLambdaArgumentTypes("(Dynamic)->Dynamic", 1) == null,
			"Stage3 must not guess one native representation for an ordinary Dynamic function parameter.");
		final assignmentTypes:Map<String, TyType> = new Map();
		assignmentTypes.set("amount", TyType.fromHintText("Int"));
		assignmentTypes.set("unknown", TyType.fromHintText("Dynamic"));
		assertTrue(@:privateAccess EmitterStage.stage3Int64CarrierValue("haxe.Int64", EIdent("amount"), "amount",
			assignmentTypes) == "Haxe_Int64.ofInt (amount)",
			"Stage3 did not recognize a typed Int local at the Int64 carrier boundary.");
		assertTrue(@:privateAccess EmitterStage.stage3Int64CarrierValue("haxe.Int64", EIdent("unknown"), "unknown", assignmentTypes) == "unknown",
			"Stage3 must not guess that a Dynamic local uses the Int carrier.");

		final sourcePath = "test/oracle/cpp_int64_add_int_seed/src/Main.hx";
		final source = HxConditionalCompilation.filterSource(File.getContent(sourcePath), new StringMap<String>());
		final int64Source = [
			"package haxe;",
			"@:transitive abstract Int64(Int) from Int to Int {",
			"  public static function ofInt(value:Int):Int64 return cast value;",
			"  public static function make(high:Int, low:Int):Int64 return cast low;",
			"  public static function toStr(value:Int64):String return '';",
			"  public static function add(left:Int64, right:Int64):Int64 return left;",
			"  public static function mul(left:Int64, right:Int64):Int64 return left;",
			"  @:op(A + B) @:commutative private static inline function addInt(value:Int64, amount:Int):Int64 return value;",
			"}",
		].join("\n");
		final program = typedProgram(source, sourcePath, int64Source);

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

		final assignmentRoot = Path.join([Sys.getCwd(), ".tmp", "m14_stage3_int64_assignment"]);
		deleteRecursive(assignmentRoot);
		final assignmentSourceDir = Path.join([assignmentRoot, "source"]);
		final assignmentInt64Dir = Path.join([assignmentSourceDir, "haxe"]);
		FileSystem.createDirectory(assignmentRoot);
		FileSystem.createDirectory(assignmentSourceDir);
		FileSystem.createDirectory(assignmentInt64Dir);
		final assignmentSourcePath = Path.join([assignmentSourceDir, "Main.hx"]);
		final assignmentSource = [
			"import haxe.Int64;",
			"class Main {",
			"  static function main():Void {",
			"    var value:Int64;",
			"    value = 1;",
			"    value = -10;",
			"    value = Int64.ofInt(5);",
			"    value = Int64.mul(value, 2);",
			"    Sys.println(Int64.toStr(value));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(assignmentSourcePath, assignmentSource);
		File.saveContent(Path.join([assignmentInt64Dir, "Int64.hx"]), int64Source);
		try {
			final executable = EmitterStage.emitToDir(typedProgram(assignmentSource, assignmentSourcePath, int64Source), assignmentRoot, true);
			final generatedMain = File.getContent(Path.join([assignmentRoot, "Main.ml"]));
			assertTrue(generatedMain.indexOf("Haxe_Int64.ofInt (1)") >= 0, "Stage3 did not convert a positive Int before storing it in an Int64 local.");
			assertTrue(generatedMain.indexOf("Haxe_Int64.ofInt ((HxInt.neg (10)))") >= 0,
				"Stage3 did not convert a negative Int before storing it in an Int64 local.");
			assertTrue(generatedMain.indexOf("Haxe_Int64.ofInt (Haxe_Int64.ofInt (5))") < 0,
				"Stage3 converted an expression that was already represented as Int64.");
			assertTrue(generatedMain.indexOf("Haxe_Int64.mul ((!value)) (Haxe_Int64.ofInt (2))") >= 0,
				"Stage3 did not convert an Int supplied to an Int64 function parameter.");

			final executed = commandOutput(executable);
			assertTrue(executed.code == 0, "focused Stage3 Int-to-Int64 assignment executable failed: " + executed.stderr);
			assertTrue(executed.stdout == "10\n", "unexpected focused Stage3 Int-to-Int64 assignment stdout:\n" + executed.stdout);
		} catch (error:Dynamic) {
			Sys.println("debug_out=" + assignmentRoot);
			throw error;
		}
		deleteRecursive(assignmentRoot);
	}
}
