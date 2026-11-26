import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A suffixed integer literal has its suffix's type, as in upstream Haxe 4.3.7
	(haxe_ocaml-st8tx). Fixture: `test/fixtures/int_literal_suffix`.

	Upstream types `7i32` as Int, `7u32` as UInt and `7i64` as haxe.Int64 (`typer.ml`, lines
	1867-1888). The parser lowers these literals to `__hxhx_int_literal(raw, suffix)`, which the
	typer did not know, so the literal had no type and a generic call such as `eq(7i32, 7)` failed
	(upstream unit `TestNumericSuffixes`).

	- `Main` must type; upstream prints `expected.stdout`.
	- `Wrong` (`final text:String = 7i32`) must fail, as upstream reports `Int should be String`.
	  Before this change the literal had no type, so hxhx accepted it.
**/
class M14IntLiteralSuffixTest {
	static final root = "test/fixtures/int_literal_suffix";

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
			".tmp/m14-int-literal-suffix/" + main,
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
		require(upstreamWrong.code != 0 && upstreamWrong.output.indexOf("Int should be String") >= 0,
			"upstream no longer rejects Wrong as recorded:\n" + upstreamWrong.output);

		final accepted = compile("Main");
		require(accepted.code == 0, "suffixed integer literals were rejected:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0, "an i32 literal was accepted as a String:\n" + rejected.output);
		Sys.println("m14_int_literal_suffix_test ok");
	}
}
