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
	  `return`, a method call on the new value inside the constructor, a
	  static field initializer, and methods and a static factory that use the
	  value.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A constructor that never assigns `this`, and `this = value` in a
	  non-inline method, are rejected by upstream Haxe. Stage3 must reject
	  both at emit time with a named error instead of emitting a placeholder.
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

	static function compareWithUpstream(source:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_abstract_this_constructor";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_ABSTRACT_THIS_CONSTRUCTOR_WHOLE_FILE:PASS");
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
			"Missing this = value", "abstract constructor Main.Mark.new never assigns this");
		rejectLikeUpstream("method_assignment",
			'abstract Mark(Int) {\n\tpublic function new()\n\t\tthis = 1;\n\n\tpublic function reset():Int {\n\t\tthis = 5;\n\t\treturn this;\n\t}\n}\n' +
			'class Main {\n\tstatic function main() {\n\t\tSys.println(new Mark().reset());\n\t}\n}\n',
			"Abstract 'this' value can only be modified inside an inline function", "assigns this outside an abstract constructor");
		compareWithUpstream("test/fixtures/stage3_abstract_this_constructor");
	}
}
