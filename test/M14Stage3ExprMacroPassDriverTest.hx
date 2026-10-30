import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	Drive the pre-typing expression macro pass through the real `Stage3Compiler`
	request path, with the default in-process macro session every non-type-only
	compile opens. Fixture: `test/fixtures/expr_macro_pass_driver`.

	- A module first loaded while the pass selects calls must still have its
	  method bodies typed under `--hxhx-no-emit` (the `--no-output` lane), so a
	  body error there fails the request exactly as it does without the pass.
	- A selected macro that cannot run is reported on stdout and fails the compile, except
	  hxhx's own `CompilerBundledSourcesMacro.files()`, which stays reported but non-fatal.
	- In a macro compilation, macro code calling another macro function is reported as
	  "macro-in-macro", the error upstream Haxe 4.3.7 gives.
**/
class M14Stage3ExprMacroPassDriverTest {
	static final root = "test/fixtures/expr_macro_pass_driver";

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function compile(main:String, ?classPathFlag:String, ?classPath:String):{code:Int, stdout:String, stderr:String} {
		final request = CompilationRequestContext.server(1);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-out",
			".tmp/m14-expr-macro-pass-driver/" + main,
			classPathFlag == null ? "-cp" : classPathFlag,
			classPath == null ? root : classPath,
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

		// A selected macro that cannot run is a compile error at the call; it is never typed as an ordinary call.
		final unexecuted = compile("Unexecuted");
		require(unexecuted.code != 0, "a selected macro that could not run did not fail the compile:\n" + unexecuted.stdout + unexecuted.stderr);
		require(unexecuted.stdout.indexOf("expr_macro_unexecuted[0]=") >= 0
			&& unexecuted.stdout.indexOf("expression macro macros.Macros.items was not executed: ") >= 0
			&& unexecuted.stdout.indexOf("Unexecuted.hx") >= 0,
			"the unexecuted macro error does not name the call and its reason:\n"
			+ unexecuted.stdout
			+ unexecuted.stderr);
		require(unexecuted.stdout.indexOf("stage3=no_emit_ok") < 0, "the compile continued after an unexecuted macro:\n" + unexecuted.stdout);

		// hxhx's own bundled-source macro is the one scoped exception until it runs through the plugin path.
		final bundled = compile("BundledSources");
		require(bundled.code == 0, "the bundled-source macro opt-out failed the compile:\n" + bundled.stdout + bundled.stderr);
		require(bundled.stdout.indexOf("expr_macro_unexecuted[0]=") >= 0
			&& bundled.stdout.indexOf("CompilerBundledSourcesMacro.files") >= 0,
			"the bundled-source macro was not reported as unexecuted:\n" + bundled.stdout);

		// In a macro compilation, macro code that calls another macro function is "macro-in-macro",
		// which upstream Haxe 4.3.7 rejects; the call is reported with that reason.
		final chain = compile("MacroChain", "--hxhx-macro-classpath", root + "/chain");
		require(chain.stdout.indexOf("MacroChain.inner: macro-in-macro") >= 0,
			"a macro-to-macro call was not reported as macro-in-macro:\n" + chain.stdout + chain.stderr);

		// A compile with no project macros still runs the pass (the built-in date macros are always
		// allowlisted) and walks standard-library switch scopes it cannot prove. That coverage count is a
		// trace diagnostic: ordinary output must not change, and HXHX_TRACE_EXPR_MACROS=1 still shows it.
		final ordinary = compile("Ordinary");
		require(ordinary.code == 0, "ordinary compile failed:\n" + ordinary.stdout + ordinary.stderr);
		require(ordinary.stdout.indexOf("expr_macro_scope_gaps=") < 0 && ordinary.stdout.indexOf("expr_macros_unexecuted=") < 0,
			"ordinary compile printed macro selection diagnostics:\n" + ordinary.stdout + ordinary.stderr);
		Sys.putEnv("HXHX_TRACE_EXPR_MACROS", "1");
		final traced = compile("Ordinary");
		Sys.putEnv("HXHX_TRACE_EXPR_MACROS", "");
		require(traced.stdout.indexOf("expr_macro_scope_gaps=") >= 0, "traced compile did not report scope gaps:\n" + traced.stdout + traced.stderr);

		Sys.println("M14_STAGE3_EXPR_MACRO_PASS_DRIVER:PASS");
	}
}
