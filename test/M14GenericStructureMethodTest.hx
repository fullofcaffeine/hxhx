import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A class's generic method satisfies a generic structure method, as in upstream Haxe 4.3.7
	(haxe_ocaml-su55u). Fixture: `test/fixtures/generic_structure_method`.

	Upstream unifies a class instance with a structure field by field. It replaces the class
	method's own type parameters with fresh monomorphs and keeps the structure method's
	parameters rigid (`src/core/tUnification.ml`, lines 723-770). So `[1]` satisfies
	`{function map<T>(s:Int->T):Array<T>;}` (upstream unit `AnonFieldAccess.unit.hx`). hxhx
	rejected every generic method there: "class value does not satisfy its structural type".

	- `Main` (generic and non-generic structure methods, and a generic class) must type; upstream
	  prints `expected.stdout`.
	- `Wrong` (a non-generic class method for a generic structure method) must still fail, as
	  upstream reports `String should be get.T`.
**/
class M14GenericStructureMethodTest {
	static final root = "test/fixtures/generic_structure_method";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function compile(main:String):{code:Int, output:String} {
		final request = CompilationRequestContext.server(1);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-out",
			".tmp/m14-generic-structure-method/" + main,
			"-cp",
			root,
			"-main",
			main
		], request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		return {code: code, output: output.toString()};
	}

	static function upstream(main:String):{code:Int, output:String} {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", main, "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, output: stdout + stderr};
	}

	static function main():Void {
		final expected = upstream("Main");
		require(expected.code == 0 && expected.output == sys.io.File.getContent(root + "/expected.stdout"),
			"the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected.output);
		final upstreamWrong = upstream("Wrong");
		require(upstreamWrong.code != 0 && upstreamWrong.output.indexOf("String should be get.T") >= 0,
			"upstream no longer rejects Wrong as recorded:\n" + upstreamWrong.output);

		final accepted = compile("Main");
		require(accepted.code == 0, "a generic class method was rejected for a generic structure method:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0 && rejected.output.indexOf("class value does not satisfy its structural type") >= 0,
			"a non-generic method was accepted for a generic structure method, or reported differently:\n" + rejected.output);
		Sys.println("m14_generic_structure_method_test ok");
	}
}
