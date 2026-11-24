import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A record with open fields stored in a local unifies with a typedef'd record parameter, as in
	upstream Haxe 4.3.7 (haxe_ocaml-u5s68). Fixture: `test/fixtures/enum_arg_open_literal`.

	Upstream `tests/unit/src/unit/UnitBuilder.hx` builds `var func = {args: [], ret: null,
	params: [], expr: ...}` and passes `FFun(func)`. hxhx typed the local as
	`{args:Array<Unknown>, ret:Null, ...}`, and call selection gave up on any argument with an
	unknown component, so the call failed with "No compatible method signature for FFun". That
	was Gate 1 Lite's first failure once constant-argument macros worked.

	- `Main` (the UnitBuilder shape, a record whose only open field is `ret: null`, a plain
	  `Function` parameter, and UnitBuilder's shape inside a local function, where hxhx sees the
	  open fields as `Dynamic`) must type; upstream prints `expected.stdout`.
	- `Wrong` (an open record whose `expr` is an `Int`) must still fail, as upstream reports
	  `Int should be haxe.macro.Expr`.
**/
class M14EnumArgOpenLiteralTest {
	static final root = "test/fixtures/enum_arg_open_literal";

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
			".tmp/m14-enum-arg-open-literal/" + main,
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

	static function upstreamOutput():String {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, "upstream Haxe failed on the fixture:\n" + stdout + stderr);
		return stdout;
	}

	static function main():Void {
		require(upstreamOutput() == sys.io.File.getContent(root + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe");
		final accepted = compile("Main");
		require(accepted.code == 0, "records with open fields were rejected as call arguments:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0, "an open record with a wrong field type was accepted:\n" + rejected.output);
		Sys.println("m14_enum_arg_open_literal_test ok");
	}
}
