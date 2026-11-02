import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds abstracts whose constructors assign `this` with the Stage3 native
	emitter and compares the program with upstream Haxe.

	Why
	- An abstract has no object of its own: its value is the backing value that
	  the constructor stores with `this = value`. Stage3 used to treat
	  `new Bag()` like a class allocation and returned an empty `HxAnon`
	  object, and it dropped the `this = value` statement. A `Map`-backed
	  abstract then crashed in the native map runtime with
	  `Invalid_argument("Hashtbl: unsupported hash table format")`.

	What
	- `stage3_abstract_this_constructor` covers abstracts over `Map`, `Array`,
	  `Float`, `String`, a class, and a type parameter (in its own module),
	  constructors with required, optional, and default arguments, `this`
	  assigned after other statements, assigned twice, kept by an early
	  `return`, used as a value (`final stored = (this = [9])`), updated by
	  compound assignment on Int, Float, and String backing types, and written
	  by a closure. A method call on the new value inside the constructor, a
	  static field initializer, and methods and a static factory use the value.
	- `stage3_abstract_this_control` assigns `this` from control flow: `if`,
	  a ternary, `switch`, an array comprehension, nested control, `try`, a
	  closure, compound assignments with a control-valued right side, right
	  sides that read or write `this`, and writes used as values, on Int,
	  String, Array, and Float backing types. Control lowering used to
	  reject `this` as a destination with "control-valued assignment requires
	  a supported exact destination".
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A constructor that never assigns `this`, and `this = value` in a
	  non-inline method, are rejected by upstream Haxe. hxhx must reject both
	  with a named error instead of emitting a placeholder: typing rejects the
	  first with upstream's "Missing this = value", and Stage3 rejects the
	  second at emit time.
	- A control-valued `this` write in an inline method must also be
	  rejected with a named error. Upstream runs the abstract case, but Stage3
	  would drop the write (Bead haxe_ocaml-rs48f); upstream rejects the class case.
**/
class M14Stage3AbstractThisConstructorTest {
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

	static function compareWithUpstream(source:String, marker:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_abstract_this_" + marker.toLowerCase();
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_ABSTRACT_THIS_" + marker + ":PASS");
	}

	/** Upstream's diagnostic for a rejected program, or null when it compiles. */
	static function upstreamDiagnostic(root:String):Null<String> {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		return status == 0 ? null : stderr;
	}

	/** Both upstream Haxe and the Stage3 emitter must reject `source`; Stage3 must name the problem. */
	static function rejectLikeUpstream(name:String, source:String, upstreamText:String, stage3Text:String):Void {
		final root = ".tmp/m14_stage3_abstract_this_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final upstream = upstreamDiagnostic(root);
		if (upstream == null || upstream.indexOf(upstreamText) < 0)
			throw name + ": upstream Haxe must reject the program with <" + upstreamText + ">, got: " + upstream;
		// Typing may reject first: the typer now owns definite assignment of
		// `this` (TyAbstractConstructorInitialization) with upstream's message.
		final message = try {
			final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			null;
		} catch (error:TyperError) {
			error.message;
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		if (message == null || message.indexOf(stage3Text) < 0)
			throw name + ": Stage3 must reject the program with <" + stage3Text + ">, got: " + message;
		Sys.println("M14_STAGE3_ABSTRACT_THIS_CONSTRUCTOR_REJECT_" + name.toUpperCase() + ":PASS");
	}

	/** Stage3 must reject `source` with `stage3Text` even though upstream Haxe runs it; `upstreamStdout` records what upstream prints. */
	static function rejectUnsupported(name:String, source:String, upstreamStdout:String, stage3Text:String):Void {
		final root = ".tmp/m14_stage3_abstract_this_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: upstreamStdout});
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final message = try {
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		if (message == null || message.indexOf(stage3Text) < 0)
			throw name + ": Stage3 must reject the program at emit time with <" + stage3Text + ">, got: " + message;
		Sys.println("M14_STAGE3_ABSTRACT_THIS_CONSTRUCTOR_REJECT_" + name.toUpperCase() + ":PASS");
	}

	static function main():Void {
		// Rejected emits run first: a failed emit must leave no emitter state behind.
		rejectLikeUpstream("unassigned",
			'abstract Mark(Int) {\n\tpublic function new() {\n\t\tSys.println("made");\n\t}\n}\n' +
			'class Main {\n\tstatic function main() {\n\t\tnew Mark();\n\t}\n}\n',
			"Missing this = value", "Missing this = value");
		rejectLikeUpstream("method_assignment",
			'abstract Mark(Int) {\n\tpublic function new()\n\t\tthis = 1;\n\n\tpublic function reset():Int {\n\t\tthis = 5;\n\t\treturn this;\n\t}\n}\n' +
			'class Main {\n\tstatic function main() {\n\t\tSys.println(new Mark().reset());\n\t}\n}\n',
			"Abstract 'this' value can only be modified inside an inline function", "assigns this outside an abstract constructor");
		// Control-valued `this` writes outside an abstract constructor. An inline
		// method's own body cannot write the caller's value back yet (Bead
		// haxe_ocaml-rs48f), so Stage3 must refuse instead of dropping the write.
		final counterMain = 'class Main {\n\tstatic function main() {\n\t\tvar c = new Counter(4);\n\t\tSys.println(c.bump(true));\n\t\tSys.println(c.value());\n\t}\n}\n';
		final controlThisOutsideConstructor = "control-valued assignment to this is supported only in constructors";
		rejectUnsupported("inline_control",
			'abstract Counter(Int) {\n\tpublic function new(start:Int)\n\t\tthis = start;\n\n'
			+ '\tpublic inline function bump(c:Bool):Int {\n\t\tthis = if (c) this + 1 else this - 1;\n\t\treturn this;\n\t}\n\n'
			+ '\tpublic function value():Int\n\t\treturn this;\n}\n'
			+ counterMain,
			"5\n5\n", controlThisOutsideConstructor);
		rejectUnsupported("inline_control_compound",
			'abstract Counter(Int) {\n\tpublic function new(start:Int)\n\t\tthis = start;\n\n'
			+ '\tpublic inline function bump(c:Bool):Int {\n\t\tthis += if (c) 1 else -1;\n\t\treturn this;\n\t}\n\n'
			+ '\tpublic function value():Int\n\t\treturn this;\n}\n'
			+ counterMain,
			"5\n5\n", controlThisOutsideConstructor);
		rejectLikeUpstream("class_inline_control",
			'class Box {\n\tpublic var v:Int = 1;\n\n\tpublic function new() {}\n\n' +
			'\tpublic inline function set(c:Bool):Int {\n\t\tthis = if (c) new Box() else this;\n\t\treturn v;\n\t}\n}\n' +
			'class Main {\n\tstatic function main() {\n\t\tSys.println(new Box().set(true));\n\t}\n}\n',
			"This expression cannot be accessed for writing", controlThisOutsideConstructor);
		compareWithUpstream("test/fixtures/stage3_abstract_this_constructor", "CONSTRUCTOR_WHOLE_FILE");
		compareWithUpstream("test/fixtures/stage3_abstract_this_control", "CONTROL_WHOLE_FILE");
	}
}
