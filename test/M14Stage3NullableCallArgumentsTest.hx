import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds programs that pass nullable primitives to concrete parameters and compares them with upstream Haxe.

	Why
	- Stage3 keeps a `Null<Int>` or `Null<Float>` in a boxed
	  carrier, while a concrete `Int` parameter takes a native OCaml `int`.
	  Ordinary calls already converted at that boundary, but the native call
	  adapters did not. `String.fromCharCode(Std.parseInt("65"))`,
	  `values.push(nullableInt)`, `map.set(nullableInt, v)`, and
	  `Math.abs(nullableInt)` passed the carrier straight through, and ocamlopt
	  rejected the program ("This expression has type Obj.t but an expression
	  was expected of type int").

	What
	- `stage3_nullable_call_arguments` passes non-null nullable values to the
	  standard static call, ordinary static, instance, and constructor calls,
	  Array, Map, and String methods, and `Math.abs`. The native executable must
	  print exactly what upstream Haxe 4.3.7 prints.
	- `stage3_nullable_call_arguments_null` is native-only. It pins the null cases:
	  the unwrap throws the catchable Haxe String "Null Access", and optional
	  Int slots read null as omitted. The fixture lists where eval agrees
	  (fromCharCode, Map keys, Math.abs, optional slots) and where it differs
	  (Haxe Int parameters, and push, insert, unshift, indexOf, contains, and
	  remove on Array<Int>).
**/
class M14Stage3NullableCallArgumentsTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function runNative(source:String, expected:String, label:String):Void {
		final path = source + "/Main.hx";
		final outDir = ".tmp/m14_stage3_nullable_call_arguments_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_NULLABLE_CALL_ARGUMENTS_" + label.toUpperCase() + ":PASS");
	}

	static function main():Void {
		final source = "test/fixtures/stage3_nullable_call_arguments";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		runNative(source, expected, "upstream");
		final nullSource = "test/fixtures/stage3_nullable_call_arguments_null";
		runNative(nullSource, File.getContent(nullSource + "/expected.native.stdout"), "null");
	}
}
