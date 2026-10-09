/** Native callback adapters must keep each argument distinct from its neighbors and authored locals. */
class M14CallableParameterIdentityTest {
	static function main():Void {
		for (entry in [
			{
				name: "two_arguments",
				source: "class Main { static function first(left:Dynamic,right:Dynamic):Dynamic return left; " +
				"static function apply(callback:(Int,Int)->Dynamic):Dynamic return callback(2,3); " +
				"static function main():Void { Sys.println(apply(first)); } }",
				expected: "2\n"
			},
			{
				name: "mixed_arguments",
				source: "class Main { static function choose(left:Dynamic,middle:Dynamic,right:Dynamic):Dynamic { Sys.println(left); Sys.println(middle); return right; } " +
				"static function apply(callback:(Int,String,Bool)->Bool):Bool return callback(7,'text',true); " +
				"static function main():Void { Sys.println(apply(choose)); } }",
				expected: "7\ntext\ntrue\n"
			},
			{name: "authored_names",
				source: "class Main { static function first(left:Dynamic,right:Dynamic):Dynamic return left; "
				+ "static function apply(callback:(Int,Int)->Dynamic):Dynamic return callback(4,9); "
				+ "static function main():Void { var __hx_callback_arg_0=11; var __hx_callback_arg_1=12; "
				+ "Sys.println(apply(first)); Sys.println(__hx_callback_arg_0); Sys.println(__hx_callback_arg_1); } }",
				expected: "4\n11\n12\n"
			}
		]) {
			final root = ".tmp/callable_parameter_identity_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, entry.source);
			observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], entry.expected);
			Sys.println("CALLABLE_PARAMETER_UPSTREAM:PASS " + entry.name);
			final module = new ResolvedModule("Main", path, ParserStage.parse(entry.source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
			observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable], entry.expected);
			if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
				throw "callback emission changed typed source";
			Sys.println("CALLABLE_PARAMETER_NATIVE:PASS " + entry.name);
		}
	}

	/** Compare actual process output with an expectation written independently of generated code. */
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "callback parameter contract differs: " + output + errors;
	}
}
