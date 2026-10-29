import haxe.io.Path;
import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	Proves Python runtime type checks against upstream Haxe's Python target.

	The fixture exercises `Std.isOfType` and `is` for Int, Float, Bool, String,
	Dynamic, Array, `null`, and user classes with inheritance, inside function
	bodies and static and instance field initializers. The program is typed with
	its whole standard-library dependency closure, so unemitted library bodies
	that contain their own runtime type checks (such as `haxe.Int64.isInt64`)
	are part of the input, as they are for the command-line compiler.

	Unsupported operands must be rejected before any output is written.
**/
class M14PythonRuntimeTypeOperandsIntegrationTest {
	static final fixture = "test/python_runtime_type_operands";

	static function run(command:String, arguments:Array<String>):String {
		final process = new Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " exited " + code + ": " + errors;
		return StringTools.replace(output, "\r\n", "\n");
	}

	/**
		Compile through the real Stage3 request pipeline: the whole standard
		library dependency closure is typed and prepared exactly as for the CLI.
		Returns the exit code and the captured compiler output.
	**/
	static function compile(sourceRoot:String, output:String):{code:Int, output:String} {
		final context = new CompilationRequestContext(0, true, false);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-backend",
			"python-native",
			"-cp",
			sourceRoot,
			"-main",
			"Main",
			"-python",
			output
		], context);
		final text = context.output.events().map(event -> event.text).join("");
		context.close(code == 0);
		return {code: code, output: text};
	}

	static function checkFixture(root:String):Void {
		final expected = File.getContent(fixture + "/expected.stdout");
		final upstream = root + "/upstream.py";
		run("haxe", ["-cp", fixture, "-main", "Main", "-python", upstream]);
		if (run("python3", [upstream]) != expected)
			throw "upstream Python runtime type behavior differs from the authored expectation";
		final compiled = compile(fixture, root + "/hxhx/main.py");
		if (compiled.code != 0)
			throw "hxhx Python compilation failed:\n" + compiled.output;
		final actual = run("python3", [root + "/hxhx/main.py"]);
		if (actual != expected) {
			File.saveContent(root + "/actual.stdout", actual);
			throw "hxhx Python runtime type behavior differs from upstream; artifacts: " + root;
		}
	}

	/** An unsupported operand reports its reason and leaves earlier output untouched. */
	static function checkRejection(root:String, name:String, source:String, expected:String, ?modules:Map<String, String>):Void {
		final sourceRoot = root + "/" + name;
		FileSystem.createDirectory(sourceRoot);
		File.saveContent(sourceRoot + "/Main.hx", source);
		if (modules != null)
			for (path => text in modules) {
				FileSystem.createDirectory(Path.directory(sourceRoot + "/" + path));
				File.saveContent(sourceRoot + "/" + path, text);
			}
		final output = sourceRoot + "/out";
		FileSystem.createDirectory(output);
		File.saveContent(output + "/main.py", "previous-output\n");
		final compiled = compile(sourceRoot, output + "/main.py");
		if (compiled.code == 0 || compiled.output.indexOf(expected) < 0)
			throw "Python did not reject " + name + " precisely: " + compiled.output;
		if (File.getContent(output + "/main.py") != "previous-output\n" || FileSystem.readDirectory(output).length != 1)
			throw "Python changed output before rejecting " + name;
	}

	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/.tmp/python_runtime_type_operands_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		checkFixture(root);
		final unsupported = "Python source target does not support runtime type operands";
		checkRejection(root, "interface",
			"interface Named {} class Main { static function main():Void { var v:Dynamic = 1; Sys.println(Std.isOfType(v, Named)); } }",
			unsupported + ": runtime-nominal:Main.Named");
		checkRejection(root, "enum",
			"enum Choice { One; } class Main { static function main():Void { var v:Dynamic = One; Sys.println(Std.isOfType(v, Choice)); } }",
			unsupported + ": runtime-enum:Main.Choice");
		checkRejection(root, "class-meta", "class Main { static function main():Void { var v:Dynamic = Main; Sys.println(Std.isOfType(v, Class)); } }",
			unsupported + ": runtime-core:Class");
		checkRejection(root, "computed-type", "class Main { static function main():Void { var t:Dynamic = Main; Sys.println(Std.isOfType(1, t)); } }",
			unsupported + " in Std.isOfType");
		checkRejection(root, "core-value", "class Main { static function main():Void { var t:Dynamic = Int; Sys.println(t); } }",
			unsupported + " as core type values");
		checkRejection(root, "library-class",
			"class Main { static function main():Void { var v:Dynamic = new haxe.ds.StringMap<Int>(); Sys.println(Std.isOfType(v, haxe.ds.StringMap)); } }",
			unsupported + ": runtime-nominal:haxe.ds.StringMap");
		checkRejection(root, "extern-class",
			'@:native("int") extern class PyInt {} class Main { static function main():Void { var v:Dynamic = 1; Sys.println(Std.isOfType(v, PyInt)); } }',
			unsupported + ": runtime-nominal:Main.PyInt");
		checkRejection(root, "compile-time-only-class",
			"class MacroHelper { macro public static function make() return macro null; }" +
			" class Main { static function main():Void { var v:Dynamic = 1; Sys.println(Std.isOfType(v, MacroHelper)); } }",
			unsupported + ": runtime-nominal:Main.MacroHelper");
		// Python emits one class per Python name, so neither same-named class can answer a test.
		checkRejection(root, "name-collision",
			"class Main { static function main():Void { var v:Dynamic = new a.Foo(); Sys.println(Std.isOfType(v, a.Foo) || Std.isOfType(v, b.Foo)); } }",
			unsupported + ": runtime-nominal:a.Foo", [
				"a/Foo.hx" => "package a; class Foo { public function new() {} }",
				"b/Foo.hx" => "package b; class Foo { public function new() {} }"
			]);
		// Unemitted library functions cannot receive a Python class object.
		checkRejection(root, "downcast",
			"class A { public function new() {} } class B extends A { public function new() super(); }" +
			" class Main { static function main():Void { var v:A = new B(); Sys.println(Std.downcast(v, B) != null); } }",
			unsupported + " passed to Std.downcast");
		checkRejection(root, "create-instance",
			"class A { public function new() {} } class Main { static function main():Void { Sys.println(Type.createInstance(A, []) != null); } }",
			unsupported + " passed to Type.createInstance");
		checkRejection(root, "deprecated-is", "class Main { static function main():Void { Sys.println(Std.is(1, Int)); } }", unsupported
			+ " passed to Std.is");
		removeTree(root);
		Sys.println("PYTHON_RUNTIME_TYPE_OPERANDS:PASS");
	}
}
