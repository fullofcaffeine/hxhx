import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A compound assignment reuses an abstract's binary operator whose result type is inferred, as in
	upstream Haxe 4.3.7 (haxe_ocaml-bps3m). Fixture: `test/fixtures/abstract_compound_inferred_op`.

	Upstream rewrites `a += 1` as `a = a + 1` and selects `@:op(A + B)`. hxhx's compound path
	reuses the base operator only when its result fits the destination, and it read the result
	from the declared signature, which is unknown for an operator without a written return type:
	"No applicable abstract binary operator += for A and Int" (upstream unit issues/Issue4681,
	Issue3345). The effective signature now supplies the inferred result.

	- `Main` must type; upstream prints `expected.stdout`.
	- `Wrong` (the operator returns Int, the destination is A) must still fail, as upstream reports
	  `Int should be A`.
**/
class M14AbstractCompoundInferredOpTest {
	static final root = "test/fixtures/abstract_compound_inferred_op";

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
			".tmp/m14-abstract-compound-inferred-op/" + main,
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
		require(upstreamWrong.code != 0 && upstreamWrong.output.indexOf("Int should be A") >= 0,
			"upstream no longer rejects Wrong as recorded:\n" + upstreamWrong.output);

		final accepted = compile("Main");
		require(accepted.code == 0, "a compound assignment through an operator with an inferred result was rejected:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0 && rejected.output.indexOf("No applicable abstract binary operator +=") >= 0,
			"an operator result that does not fit the destination was accepted, or reported differently:\n" + rejected.output);
		Sys.println("m14_abstract_compound_inferred_op_test ok");
	}
}
