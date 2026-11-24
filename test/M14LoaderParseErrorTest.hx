import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A module that typing loads on demand must report its parse error, as upstream
	Haxe 4.3.7 does. Fixture: `test/fixtures/loader_parse_error`.

	`Main` calls `Util.answer()`; `Util.hx` has a header syntax error. Upstream
	prints `Util.hx:1: characters 20-21 : Unexpected {` and fails. Before
	haxe_ocaml-kq23l, `ModuleLoader` dropped the module silently, so the compile
	reported an unrelated typing error in `Main.hx` instead. hxhx reports the
	failure as its eager resolver does (`parse_failed <file>: <message>`); its
	parser's message text still differs from upstream's.
**/
class M14LoaderParseErrorTest {
	static final root = "test/fixtures/loader_parse_error";

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
			".tmp/m14-loader-parse-error/" + main,
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

	static function main():Void {
		final demanded = compile("Main");
		require(demanded.code != 0, "a parse error in a module that typing loaded did not fail the compile:\n" + demanded.output);
		require(demanded.output.indexOf("parse_failed ") >= 0 && demanded.output.indexOf("loader_parse_error/Util.hx: ") >= 0,
			"the parse error of the loaded module was not reported against its file:\n" + demanded.output);
		require(demanded.output.indexOf("selected call conversion") < 0,
			"the dropped module was reported as a typing error at the call site:\n" + demanded.output);
		Sys.println("m14_loader_parse_error_test ok");
	}
}
