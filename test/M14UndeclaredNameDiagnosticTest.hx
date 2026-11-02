import sys.FileSystem;
import sys.io.File;

/**
	Names that no declaration provides must be rejected while typing, with
	upstream Haxe 4.3.7's message.

	Why
	- The typer gave an unresolved title-case name such as `Run` the type
	  String (a legacy enum-tag path), typed `Nope.foo()` on an unknown
	  receiver as an unknown value, and kept an import that names nothing as
	  an unresolved directive. `--no-output` therefore succeeded for programs
	  that upstream rejects, and emission later failed with an unrelated message
	  (haxe_ocaml-db83a, haxe_ocaml-ikrmd).

	What
	- Each invalid program must be rejected by upstream and by hxhx typing,
	  with the same message and line. The `--hxhx-no-emit` driver lane, where
	  the bugs were reported, must fail too.
	- `undeclared_names_valid` covers the names that must stay accepted:
	  module and imported enum constructors, a local with a title-case name, a
	  class value, a typedef receiver, a static member import, a sub-type
	  import, an import used only by macros, an empty package wildcard, an
	  import removed by conditional compilation, an `@:native` extern, and
	  untyped host names. Upstream runs it; hxhx must type it.
**/
class M14UndeclaredNameDiagnosticTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function upstreamDiagnostic(root:String):Null<String> {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		return status == 0 ? null : stderr;
	}

	static function hxhxDiagnostic(root:String):Null<String> {
		final path = root + "/Main.hx";
		return try {
			M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: root});
			null;
		} catch (error:TyperError) {
			error.toString();
		}
	}

	/** Upstream and hxhx must both reject `source` with a message containing `message`, on `line`. */
	static function reject(name:String, source:String, message:String, line:Int):Void {
		final root = ".tmp/m14_undeclared_names_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final upstream = upstreamDiagnostic(root);
		if (upstream == null || upstream.indexOf("Main.hx:" + line + ":") < 0 || upstream.indexOf(message) < 0)
			throw name + ": upstream must reject on line " + line + " with <" + message + ">, got: " + upstream;
		final actual = hxhxDiagnostic(root);
		if (actual == null || actual.indexOf("Main.hx:" + line + ":") < 0 || actual.indexOf(message) < 0)
			throw name + ": hxhx typing must reject on line " + line + " with <" + message + ">, got: " + actual;
		deleteRecursive(root);
		Sys.println("M14_UNDECLARED_NAMES_REJECT_" + name.toUpperCase() + ":PASS");
	}

	/** The original reports used the no-emit driver lane; it must fail instead of reporting no_emit_ok. */
	static function rejectNoEmit(name:String, source:String):Void {
		final root = ".tmp/m14_undeclared_names_driver_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final code = hxhx.Stage3Compiler.run([
			"-cp",
			root,
			"-main",
			"Main",
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-out",
			root + "/out"
		]);
		if (code == 0)
			throw name + ": the no-emit driver must fail for an undeclared name";
		deleteRecursive(root);
		Sys.println("M14_UNDECLARED_NAMES_NO_EMIT_" + name.toUpperCase() + ":PASS");
	}

	static function main():Void {
		final main = (body:String) -> "class Main {\n\tstatic function main():Void {\n\t\t" + body + "\n\t}\n}\n";
		reject("static_call", main("Nope.foo();"), "Type not found : Nope", 3);
		reject("static_read", main("final x = Nope.foo;"), "Type not found : Nope", 3);
		reject("enum_like_value", main("var mode = Run;"), "Unknown identifier : Run", 3);
		reject("enum_like_switch",
			"class Main {\n\tstatic function main() {\n\t\tvar mode = Run;\n\t\tswitch (mode) {\n\t\t\tcase Build: Sys.println(\"build\");\n\t\t\tcase Run: Sys.println(\"run\");\n\t\t}\n\t}\n}\n",
			"Unknown identifier : Run", 3);
		reject("missing_import", "import does.not.Exist;\n" + main(""), "Type not found : does.not.Exist", 1);
		reject("missing_alias_import", "import does.not.Exist as E;\n" + main(""), "Type not found : does.not.Exist", 1);
		reject("missing_using", "using does.not.Exist;\n" + main(""), "Type not found : does.not.Exist", 1);
		reject("missing_member_import", "import haxe.Json.nope;\n" + main(""), "Class<haxe.Json> has no field nope", 1);
		rejectNoEmit("static_call", main("Nope.foo();"));
		rejectNoEmit("missing_import", "import does.not.Exist;\n" + main(""));
		rejectNoEmit("enum_like_value", main("var mode = Run;"));
		final valid = "test/fixtures/undeclared_names_valid";
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", valid, "--run", "Main"],
			expected: File.getContent(valid + "/expected.stdout")
		});
		final accepted = hxhxDiagnostic(valid);
		if (accepted != null)
			throw "valid_names: hxhx typing must accept the declared and untyped names, got: " + accepted;
		Sys.println("M14_UNDECLARED_NAMES_VALID:PASS");
	}
}
