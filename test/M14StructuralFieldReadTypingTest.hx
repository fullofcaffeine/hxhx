import backend.BackendContext;
import backend.js.JsBackend;
import sys.io.File;

/** Field reads must retain structural and Dynamic types before target conversion. */
class M14StructuralFieldReadTypingTest {
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "structural field observer failed: " + stdout + stderr;
	}

	static function main():Void {
		final source = 'class Main {'
			+ 'static function record(value:{flag:Bool}):Bool { return value.flag; }'
			+ 'static function nested(value:{inner:{count:Int}}):Int { return value.inner.count; }'
			+ 'static function dynamicField(value:Dynamic):Dynamic { return value.flag; }'
			+ 'static function nullable(value:Null<{flag:Bool}>):Null<Bool> { return value?.flag; }'
			+ '}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		if (typed.getTypedClasses()[0].getFunctions().length != 4)
			throw "structural field fixture lost a function";
		for (fn in typed.getTypedClasses()[0].getFunctions()) {
			final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
			final expected = switch name {
				case "record": TyType.fromHintText("Bool");
				case "nested": TyType.fromHintText("Int");
				case "dynamicField": TyType.fromHintText("Dynamic");
				case "nullable": TyType.fromHintText("Null<Bool>");
				case _: throw "unexpected fixture function";
			};
			final actual = fn.getBody().getStatements()[0].getExpressions()[0].getType();
			if (actual.getSemanticKey() != expected.getSemanticKey())
				throw name + " field read lost its type: " + actual.getSemanticKey();
		}
		final previousStrict = Sys.getEnv("HXHX_TYPER_STRICT");
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		var rejected = false;
		try {
			final invalid = new ResolvedModule("Missing", "Missing.hx",
				ParserStage.parse('class Missing { static function read(value:{flag:Bool}):Bool { return value.absent; } }', "Missing.hx"));
			TyperStage.typeResolvedModule(invalid, TyperIndex.build([invalid]));
		} catch (error:TyperError) {
			rejected = error.toString().indexOf("Unknown field absent") >= 0;
		}
		Sys.putEnv("HXHX_TYPER_STRICT", previousStrict == null ? "" : previousStrict);
		if (!rejected)
			throw "missing required field was accepted in strict mode";
		Sys.println("M14_STRUCTURAL_FIELD_TYPES:PASS");
		final root = "test/fixtures/structural_field_read";
		final expected = File.getContent(root + "/expected.stdout");
		observe("haxe", ["-cp", root, "--run", "Main"], expected);
		final runtimeModule = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(File.getContent(root + "/Main.hx"), root + "/Main.hx"));
		final runtimeTyped = TyperStage.typeResolvedModule(runtimeModule, TyperIndex.build([runtimeModule]));
		final script = ".tmp/structural-field-read/Main.js";
		new JsBackend().emit(new MacroExpandedProgram([runtimeTyped], false),
			new BackendContext(".tmp/structural-field-read", script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		observe("node", ["--check", script], "");
		observe("node", [script], expected);
		Sys.println("M14_STRUCTURAL_FIELD_READ_TYPING:PASS");
	}
}
