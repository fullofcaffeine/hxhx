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
	static function reject(name:String, source:String, message:String, line:Int, ?providers:Array<{path:String, source:String}>):Void {
		final root = ".tmp/m14_undeclared_names_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		for (provider in (providers == null ? [] : providers)) {
			FileSystem.createDirectory(haxe.io.Path.directory(root + "/" + provider.path));
			File.saveContent(root + "/" + provider.path, provider.source);
		}
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

	/** One program file written under a test root, relative to that root. */
	static function writeProgram(root:String, source:String, files:Array<{path:String, source:String}>):Void {
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		for (file in files) {
			FileSystem.createDirectory(haxe.io.Path.directory(root + "/" + file.path));
			File.saveContent(root + "/" + file.path, file.source);
		}
	}

	/** Run the `--hxhx-no-emit` driver lane and return its exit code. */
	static function driverExitCode(root:String, extra:Array<String>):Int {
		return hxhx.Stage3Compiler.run([
			"-cp",
			root,
			"-main",
			"Main",
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-out",
			root + "/out"
		].concat(extra));
	}

	/**
		A program that upstream accepts, but whose declarations hxhx cannot fully
		see (a macro can add them, or `import.hx` can bring them in), must not be
		reported as naming something undeclared. `extra` holds driver-only flags
		such as `--macro`.
	**/
	static function accept(name:String, source:String, files:Array<{path:String, source:String}>, ?extra:Array<String>):Void {
		final root = ".tmp/m14_undeclared_names_open_" + name;
		writeProgram(root, source, files);
		final flags = extra == null ? [] : extra;
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"].concat(flags));
		process.stdout.readAll();
		final upstream = process.stderr.readAll().toString();
		if (process.exitCode() != 0)
			throw name + ": upstream must accept the program, got: " + upstream;
		process.close();
		if (flags.length == 0) {
			final typed = hxhxDiagnostic(root);
			if (typed != null)
				throw name + ": hxhx typing must accept the program, got: " + typed;
		}
		final code = driverExitCode(root, flags);
		if (code != 0)
			throw name + ": the no-emit driver must accept the program, exit " + code;
		deleteRecursive(root);
		Sys.println("M14_UNDECLARED_NAMES_FAIL_OPEN_" + name.toUpperCase() + ":PASS");
	}

	/**
		An expression macro receives its arguments as syntax, so `Nope` in
		`M.name(Nope.foo)` is not a name lookup and the undeclared-name check must
		not report it. Macro calls cannot expand in this interpreted test, so only
		that one diagnostic is asserted.
	**/
	static function macroArgumentIsNotChecked():Void {
		final root = ".tmp/m14_undeclared_names_open_macro_argument";
		writeProgram(root, "class Main {\n\tstatic function main():Void {\n\t\ttrace(M.name(Nope.foo));\n\t}\n}\n", [
			{path: "M.hx", source: "class M {\n\tpublic static macro function name(e:haxe.macro.Expr):haxe.macro.Expr\n\t\treturn macro \"x\";\n}\n"}
		]);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		final upstream = process.stderr.readAll().toString();
		if (process.exitCode() != 0)
			throw "macro_argument: upstream must accept the program, got: " + upstream;
		process.close();
		// Typing still stops later on the unexpanded call, with an internal
		// error that main reports too; only the name check is under test here.
		final typed = try hxhxDiagnostic(root) catch (error:Dynamic) Std.string(error);
		if (typed != null && typed.indexOf("Nope") >= 0)
			throw "macro_argument: a macro argument must not be name-checked, got: " + typed;
		deleteRecursive(root);
		Sys.println("M14_UNDECLARED_NAMES_FAIL_OPEN_MACRO_ARGUMENT:PASS");
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
		final buildMacro = {path: "Macros.hx",
			source: "import haxe.macro.Context;\nimport haxe.macro.Expr;\nclass Macros {\n"
			+ "\tpublic static macro function build():Array<Field> {\n"
			+ "\t\tfinal fields = Context.getBuildFields();\n"
			+ "\t\tfields.push({name: \"Generated\", pos: Context.currentPos(), access: [AStatic, APublic], kind: FVar(null, macro ({Foo: 1}))});\n"
			+ "\t\treturn fields;\n\t}\n}\n"};
		final parent = {path: "Parent.hx", source: "@:autoBuild(Macros.build()) class Parent {\n\tpublic function new() {}\n}\n"};
		final tagged = {path: "Tagged.hx", source: "@:autoBuild(Macros.build()) interface Tagged {}\n"};
		accept("autobuild_parent", "class Main extends Parent {\n\tstatic function main():Void {\n\t\ttrace(Generated);\n\t}\n}\n", [buildMacro, parent]);
		accept("autobuild_receiver", "class Main extends Parent {\n\tstatic function main():Void {\n\t\ttrace(Generated.Foo);\n\t}\n}\n", [buildMacro, parent]);
		accept("autobuild_interface", "class Main implements Tagged {\n\tstatic function main():Void {\n\t\ttrace(Generated);\n\t}\n}\n", [buildMacro, tagged]);
		accept("cli_add_metadata", main("trace(Generated);"), [buildMacro], ["--macro", "addMetadata('@:build(Macros.build())', 'Main')"]);
		accept("init_macro_define_type", main("trace(Generated.hi());"), [
			{
				path: "Init.hx",
				source: "import haxe.macro.Context;\nclass Init {\n\tpublic static function run():Void {\n" +
				"\t\tContext.onAfterInitMacros(() -> Context.defineType(macro class Generated {\n" +
				"\t\t\tpublic static function hi():Int return 1;\n\t\t}));\n\t}\n}\n"
			}
		], ["--macro", "Init.run()"]);
		accept("import_hx", main("trace(ViaImportHx.fn());"), [
			{path: "import.hx", source: "import pack.Cfg as ViaImportHx;\n"},
			{path: "pack/Cfg.hx", source: "package pack;\nclass Cfg {\n\tpublic static function fn():Int return 1;\n}\n"}
		]);
		macroArgumentIsNotChecked();
		accept("build_macro_defines_type", "class Main {\n\tstatic function main():Void {\n\t\tOther.x;\n\t\ttrace(Generated.hi());\n\t}\n}\n", [
			{path: "Macros.hx",
				source: "import haxe.macro.Context;\nimport haxe.macro.Expr;\nclass Macros {\n"
				+ "\tpublic static macro function build():Array<Field> {\n"
				+ "\t\tContext.defineType(macro class Generated {\n\t\t\tpublic static function hi():Int return 1;\n\t\t});\n"
				+ "\t\treturn Context.getBuildFields();\n\t}\n}\n"},
			{path: "Other.hx", source: "@:build(Macros.build()) class Other {\n\tpublic static var x = 1;\n}\n"}
		]);
		final classWith = (meta:String, body:String) -> meta + " class Main {\n\tstatic function main():Void {\n\t\t" + body + "\n\t}\n}\n";
		reject("similar_metadata_build_version", classWith("@:buildVersion(\"1\")", "trace(Run);"), "Unknown identifier : Run", 3);
		reject("similar_metadata_builder", classWith("@:builder", "Nope.foo();"), "Type not found : Nope", 3);
		reject("similar_metadata_auto_builder", classWith("@:autoBuilder", "trace(Run);"), "Unknown identifier : Run", 3);
		reject("build_in_line_comment", "// @:build(Macros.build()) was removed\n" + main("trace(Run);"), "Unknown identifier : Run", 4);
		reject("build_in_block_comment", "/* @:build(Macros.build()) */\n" + main("trace(Run);"), "Unknown identifier : Run", 4);
		reject("build_in_string", main("trace(\"@:build(\"); trace(Run);"), "Unknown identifier : Run", 3);
		reject("import_in_comment", "// import Run;\n" + main("trace(Run);"), "Unknown identifier : Run", 4);
		reject("empty_import_hx", main("trace(Run);"), "Unknown identifier : Run", 3, [{path: "import.hx", source: ""}]);
		reject("not_exempted_by_unrelated_parent", "class Main extends Parent {\n\tstatic function main():Void {\n\t\tvar mode = Run;\n\t}\n}\n",
			"Unknown identifier : Run", 3, [
			{
				path: "Parent.hx",
				source: "class Parent {\n\tpublic function new() {}\n}\n"
			}
		]);
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
		buildMacroNames();
	}

	/**
		A build macro can add the field a name refers to. The native in-process
		lane does not apply build fields yet, so the name check must leave such a
		module alone rather than report "Unknown identifier" for a valid program.
	**/
	static function buildMacroNames():Void {
		final root = ".tmp/m14_undeclared_names_build_macro";
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Macros.hx",
			'import haxe.macro.Context;\nimport haxe.macro.Expr;\n\nclass Macros {\n\tpublic static macro function build():Array<Field> {\n\t\tfinal fields = Context.getBuildFields();\n\t\tfields.push({name: "Generated", access: [AStatic, APublic], kind: FVar(macro :Int, macro 42), pos: Context.currentPos()});\n\t\treturn fields;\n\t}\n}\n');
		final source = '@:build(Macros.build())\nclass Main {\n\tstatic function main() {\n\t\tSys.println(Generated);\n\t}\n}\n';
		File.saveContent(root + "/Main.hx", source);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: "42\n"});
		final diagnostic = hxhxDiagnostic(root);
		if (diagnostic != null && diagnostic.indexOf("Unknown identifier") >= 0)
			throw "build_macro: a name a build macro adds must not be reported as unknown, got: " + diagnostic;
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
		if (code != 0)
			throw "build_macro: the no-emit driver must not reject the build-macro program (exit " + code + ")";
		deleteRecursive(root);
		Sys.println("M14_UNDECLARED_NAMES_BUILD_MACRO:PASS");
	}
}
