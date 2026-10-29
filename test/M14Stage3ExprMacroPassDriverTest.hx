import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	Drive the pre-typing expression macro pass through the real `Stage3Compiler`
	request path, with the default in-process macro session every non-type-only
	compile opens. Fixture: `test/fixtures/expr_macro_pass_driver`.

	- A module first loaded while the pass selects calls must still have its
	  method bodies typed under `--hxhx-no-emit` (the `--no-output` lane), so a
	  body error there fails the request exactly as it does without the pass.
	- A selected macro with no executor is reported on stdout before typing.
**/
class M14Stage3ExprMacroPassDriverTest {
	static final root = "test/fixtures/expr_macro_pass_driver";

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function compile(main:String):{code:Int, stdout:String, stderr:String} {
		final request = CompilationRequestContext.server(1);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-out",
			".tmp/m14-expr-macro-pass-driver/" + main,
			"-cp",
			root,
			"-main",
			main
		], request);
		final stdout = new StringBuf();
		final stderr = new StringBuf();
		for (event in request.output.events())
			(event.isErrorStream ? stderr : stdout).add(event.text);
		request.close(code == 0);
		return {code: code, stdout: stdout.toString(), stderr: stderr.toString()};
	}

	static function main():Void {
		final bodyError = compile("BodyError");
		require(bodyError.code != 0, "a body error in a module the macro pass loaded was not typed under no-emit:\n" + bodyError.stdout + bodyError.stderr);
		require((bodyError.stdout + bodyError.stderr).indexOf("project/Util.hx") >= 0,
			"body error was not attributed to the discovered module:\n" + bodyError.stdout + bodyError.stderr);

		final unexecuted = compile("Unexecuted");
		require(unexecuted.stdout.indexOf("expr_macros_unexecuted=1\n") >= 0
			&& unexecuted.stdout.indexOf("expr_macro_unexecuted[0]=") >= 0
			&& unexecuted.stdout.indexOf("macros.Macros.items") >= 0,
			"selected macro without an executor was not reported:\n"
			+ unexecuted.stdout
			+ unexecuted.stderr);

		Sys.println("M14_STAGE3_EXPR_MACRO_PASS_DRIVER:PASS");
	}
}
