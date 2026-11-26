import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A later argument of a generic call may reach the type parameter through a cast, as in upstream
	Haxe 4.3.7 (haxe_ocaml-587vc). Fixture: `test/fixtures/generic_argument_cast`.

	Upstream binds a method type parameter to the first argument that gives it a type, then
	unifies each later argument with that type, which accepts an abstract's declared casts, `Any`,
	a subclass and a `Dynamic` type argument. So `same(1, First)` with
	`enum abstract Kind(Int) to Int` binds `T` to `Int`. hxhx required the two argument types to
	unify with each other and rejected the call: "No compatible method signature for same". This
	was the largest cause in the upstream unit-test survey (35 files, mostly `eq(expected, actual)`).

	- `Main` must type; upstream prints `expected.stdout`.
	- `Wrong` (`same(First, 1)`: Int does not cast to Kind) must still fail, as upstream reports
	  `Int should be Kind`.
**/
class M14GenericArgumentCastTest {
	static final root = "test/fixtures/generic_argument_cast";

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
			".tmp/m14-generic-argument-cast/" + main,
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
		require(upstreamWrong.code != 0 && upstreamWrong.output.indexOf("Int should be Kind") >= 0,
			"upstream no longer rejects Wrong as recorded:\n" + upstreamWrong.output);

		final accepted = compile("Main");
		require(accepted.code == 0, "a generic call argument that reaches T through a cast was rejected:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0 && rejected.output.indexOf("No compatible method signature for same") >= 0,
			"an argument that does not cast to the first argument's type was accepted, or reported differently:\n" + rejected.output);
		Sys.println("m14_generic_argument_cast_test ok");
	}
}
