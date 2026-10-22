/** A stored callback keeps its checked Dynamic argument boundary and its function identity. */
class M14StoredCallbackArgumentsTest {
	static function main():Void {
		final root = ".tmp/stored_callback_arguments";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = "class Main { "
			+ "static function consume(value:Dynamic):Dynamic { Sys.println(value); return value; } "
			+ "static function select():Dynamic->Dynamic { Sys.println('select'); return consume; } "
			+ "static function make(offset:Int):Int->Int return (value:Int)->offset+value; "
			+ "static function main():Void { var callback:Dynamic->Dynamic=select(); var alias=callback; "
			+ "callback(7); callback('ok'); callback(true); callback(null); "
			+ "var number:Int=9; var text:String='local'; var flag:Bool=false; "
			+ "alias(number); alias(text); alias(flag); Sys.println(callback==alias); "
			+ "var first=make(1); var second=make(1); Sys.println(first==first); Sys.println(first==second); Sys.println(first!=second); } }";
		final expected = "select\n7\nok\ntrue\nnull\n9\nlocal\nfalse\ntrue\ntrue\nfalse\ntrue\n";
		sys.io.File.saveContent(path, source);
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("STORED_CALLBACK_ARGUMENTS_UPSTREAM:PASS");
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable], expected);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "stored callback emission changed typed source";
		Sys.println("STORED_CALLBACK_ARGUMENTS_NATIVE:PASS");
	}

	/** Observe actual native execution against values specified independently of generated code. */
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "stored callback arguments differ: " + output + errors;
	}
}
