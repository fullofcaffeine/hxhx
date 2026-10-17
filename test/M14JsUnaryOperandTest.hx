/** Negation of a signed hexadecimal Int must not become a JavaScript decrement token. */
class M14JsUnaryOperandTest {
	static function main():Void {
		final root = ".tmp/js_unary_operand";
		sys.FileSystem.createDirectory(root);
		final source = '@:native("console") extern class Console {public static function log(value:Int):Void;}'
			+ 'class Main{static function main():Void{'
			+ 'Console.log(-0xffffffff);Console.log(~0xffffffff);var value=0;Console.log(-(value=3));Console.log(value);'
			+ 'Console.log(-(-1));}}';
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]) != 0)
			throw "upstream unary compilation failed";
		final expected = "1\n0\n-3\n3\n1\n";
		observe(root + "/upstream.js", expected);
		Sys.println("JS_UNARY_OPERAND_UPSTREAM:PASS");
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(root, root + "/candidate.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		observe(root + "/candidate.js", expected);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "unary emission changed typed source";
		Sys.println("JS_UNARY_OPERAND:PASS");
	}

	/** Compare a real JS runtime with the independent expected values and side effect. */
	static function observe(path:String, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", path]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "unary operand behavior differs: " + output + errors;
	}
}
