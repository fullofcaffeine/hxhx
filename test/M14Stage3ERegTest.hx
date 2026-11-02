import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a regular-expression program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- On the OCaml target, `EReg` is an `extern` class. Its OCaml body is the
	  shared runtime file `EReg.ml`, which builds a value with `EReg.create`.
	  Stage3 had no construction route for that runtime module, so both a regex
	  literal (`~/x/`, which the parser turns into `new EReg("x", "")`) and an
	  explicit `new EReg(...)` produced the placeholder `(Obj.magic 0)`. The
	  build still succeeded, and the executable crashed on the first `match`.

	What
	- `stage3_ereg` uses literals with and without flags,
	  `new EReg(pattern, flags)`, and `match`, `matched`, `matchedLeft`,
	  `matchedRight`, `matchedPos`, `replace`, `split`, and `map`. Regexes live
	  in locals, a static field, an instance field, and a function parameter.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- The generated `Main.ml` must construct every regex in the source through
	  `EReg.create`, and every `(Obj.magic 0)` in it must be the unreachable
	  tail that follows a function's `return`.
	- `stage3_ereg_errors` pins two native-only failures: an invalid pattern
	  throws a catchable Haxe String, and a method call on an EReg held in
	  `Dynamic` throws a named Haxe error instead of crashing. Upstream cannot
	  be the oracle there: `--interp` aborts on the invalid pattern without
	  reaching `catch`, other targets word the error differently, and upstream
	  supports the Dynamic call (Bead haxe_ocaml-m2wff).
	- The named emit-time errors of `Stage3OcamlERegCalls` and the EReg
	  subclass rejection are checked directly.
**/
class M14Stage3ERegTest {
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

	static function count(text:String, needle:String):Int {
		return text.split(needle).length - 1;
	}

	/** Run `action` and require an exception whose text contains `expected`. */
	static function requireFailure(label:String, expected:String, action:() -> Void):Void {
		var message:Null<String> = null;
		try {
			action();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null)
			throw label + ": expected a failure containing <" + expected + ">, but the call succeeded";
		if (message.indexOf(expected) < 0)
			throw label + ": expected a failure containing <" + expected + ">, got <" + message + ">";
	}

	static function compareWithUpstream():Void {
		final source = "test/fixtures/stage3_ereg";
		final path = source + "/Main.hx";
		final text = File.getContent(path);
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_ereg";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: text, path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		// The fixture module emits `Main.ml` and `Main_Holder.ml`.
		final generated = File.getContent(outDir + "/Main.ml") + File.getContent(outDir + "/Main_Holder.ml");
		// Each function body ends with `raise (HxReturn_f ...) in (Obj.magic 0)) with HxReturn_f v`.
		// Any other `(Obj.magic 0)` is a placeholder for an unsupported value.
		final placeholders = count(generated, "(Obj.magic 0)");
		final returnTails = count(generated, "(Obj.magic 0)) with HxReturn_");
		if (placeholders != returnTails)
			throw "Main.ml and Main_Holder.ml have "
				+ (placeholders - returnTails)
				+ " (Obj.magic 0) placeholders outside return tails: "
				+ generated;
		// Count constructions in the code only, after the fixture's leading doc comment.
		final code = text.substr(text.indexOf("**/"));
		final constructions = count(code, "~/") + count(code, "new EReg(");
		final created = count(generated, "(EReg.create)");
		if (created != constructions)
			throw "expected " + constructions + " EReg.create calls in Main.ml and Main_Holder.ml, found " + created + ": " + generated;
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_EREG_UPSTREAM:PASS");
	}

	static function nativeFailures():Void {
		final source = "test/fixtures/stage3_ereg_errors";
		final path = source + "/Main.hx";
		final outDir = ".tmp/m14_stage3_ereg_errors";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: File.getContent(source + "/expected.native.stdout")});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_EREG_NATIVE_FAILURES:PASS");
	}

	static function namedEmitErrors():Void {
		final runtime:Map<String, Bool> = ["EReg" => true];
		requireFailure("wrong argument count", "new EReg(...) needs a pattern and flags, got 1 arguments",
			() -> backend.ocaml.Stage3OcamlERegCalls.renderConstruction({
				arguments: ["\"a\""],
				runtimeModules: runtime,
				names: null
			}));
		final withoutEReg:Map<String, Bool> = ["HxRuntime" => true];
		requireFailure("missing runtime module", "needs the OCaml runtime module EReg",
			() -> backend.ocaml.Stage3OcamlERegCalls.renderConstruction({arguments: ["\"a\"", "\"\""], runtimeModules: withoutEReg, names: null}));
		requireFailure("unknown method", "EReg.unknownMethod has no native adapter", () -> backend.ocaml.Stage3OcamlERegCalls.instanceMethod("unknownMethod"));
		final source = [
			'class Digits extends EReg {',
			'  public function new() {',
			'    super("[0-9]+", "");',
			'  }',
			'}',
			'class Main {',
			'  static function main():Void {',
			'    Sys.println(new Digits().match("a12"));',
			'  }',
			'}',
			''
		].join("\n");
		final outDir = ".tmp/m14_stage3_ereg_subclass";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: "Main.hx", root: "."});
		requireFailure("EReg subclass", "EReg is an extern runtime class and cannot be extended natively yet",
			() -> EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir));
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_EREG_NAMED_ERRORS:PASS");
	}

	static function main():Void {
		namedEmitErrors();
		compareWithUpstream();
		nativeFailures();
	}
}
