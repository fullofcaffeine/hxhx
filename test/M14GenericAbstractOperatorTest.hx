import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	An abstract operator declared with a type parameter applies, as in upstream Haxe 4.3.7
	(haxe_ocaml-tnnxn). Fixture: `test/fixtures/generic_abstract_operator`.

	Upstream gives an operator function's type parameters constrained monomorphs and binds them to
	the operand types (`operators.ml`, lines 466-520). So UInt's `equalsInt<T:Int>(a:UInt, b:T)`
	serves `u == 3` and, being commutative, `3 == u`. hxhx rejected every generic operator:
	"Generic abstract binary operator is not supported yet" (6 files in the upstream unit survey).

	- `Main` must type; upstream prints `expected.stdout`.
	- `Wrong` (`box * 1.5` against `scale<T:Int>`) must still fail: the constraint keeps the
	  operator from applying, and upstream reports `Box should be Int`.
**/
class M14GenericAbstractOperatorTest {
	static final root = "test/fixtures/generic_abstract_operator";

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
			".tmp/m14-generic-abstract-operator/" + main,
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
		require(upstreamWrong.code != 0 && upstreamWrong.output.indexOf("Box should be Int") >= 0,
			"upstream no longer rejects Wrong as recorded:\n" + upstreamWrong.output);

		final accepted = compile("Main");
		require(accepted.code == 0, "a generic abstract operator was rejected:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0, "an operator was applied against its type parameter's constraint:\n" + rejected.output);
		Sys.println("m14_generic_abstract_operator_test ok");
	}
}
