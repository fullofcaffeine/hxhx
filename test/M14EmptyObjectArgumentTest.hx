import backend.BackendContext;
import backend.js.JsBackend;
import sys.io.File;

/** Verify the syntax/type distinction and observe fresh empty objects through emitted JavaScript. */
class M14EmptyObjectArgumentTest {
	static function typed(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]), null, true);
	}

	static function checkFunction(body:String, expectedReturn:String):Void {
		final module = typed("class Main { static function main():Void { var callback = " + body + "; } }");
		final value = module.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
		if (!value.getType().isFunction() || value.getType().getFunctionReturn().getDisplay() != expectedReturn)
			throw "empty function body acquired an object return: " + body;
		if (!value.getExpressions()[0].getType().isVoid())
			throw "empty function body lost its Void completion: " + body;
	}

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "empty object observer failed: " + stdout + stderr;
	}

	static function main():Void {
		final syntax = HxParser.parseCompleteExprText("{}");
		if (!syntax.match(ESourceGroup([], _)))
			throw "empty brace syntax must remain a source group";
		final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(syntax, []), HxPos.unknown(), null).getExpressions()[0];
		if (quoted.getTag() != SourceGroup || !TypedSourceSyntax.expression(quoted).match(ESourceGroup([], _)))
			throw "quoted empty braces became an executing object";
		checkFunction("function():Void {}", "Void");
		checkFunction("() -> {}", "Void");
		checkFunction("() -> ({})", "Void");
		var rejected = false;
		try {
			typed("class Main { static function main():Void { var callback = function():Dynamic {}; } }");
		} catch (error:TyperError) {
			rejected = error.toString().indexOf("Missing return: Dynamic") >= 0;
		}
		if (!rejected)
			throw "empty function body incorrectly satisfied a written Dynamic return";
		final root = "test/fixtures/empty_object_argument_seed";
		final expected = File.getContent(root + "/expected.stdout");
		observe("haxe", ["-cp", root, "--run", "Main"], expected);
		final module = typed(File.getContent(root + "/Main.hx"));
		final script = ".tmp/empty-object-argument/Main.js";
		new JsBackend().emit(new MacroExpandedProgram([module], false),
			new BackendContext(".tmp/empty-object-argument", script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		observe("node", ["--check", script], "");
		observe("node", [script], expected);
		Sys.println("EMPTY_OBJECT_ARGUMENT:PASS");
	}
}
