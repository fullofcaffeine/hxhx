import sys.io.File;

/**
	Compare omitted-input types for `- * / %` with upstream Haxe 4.3.7, then run the native output.

	Upstream binds an unknown operand to Int when its peer is a number, Dynamic, or another
	unknown operand (`value - 1.5` gives `value : Int`). hxhx left these inputs unknown, so
	`tmp[l - 1]` in `haxe.zip.Huffman` typed `l - 1` as Float (haxe_ocaml-lisu2).
**/
class M14ArithmeticOperandInferenceTest {
	static final root = "test/fixtures/arithmetic_operand_inference";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "arithmetic inference observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final expectedTypes = File.getContent(root + "/expected.types");
		observe("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/method_parameter_dynamic_context",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"UpstreamTypes.check(\"Main.Ops\")",
			"--no-output"
		], expectedTypes);
		final expected = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("ARITHMETIC_INPUT_UPSTREAM:PASS");

		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final observations:Array<String> = [];
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Ops")
				for (fn in cls.getFunctions())
					for (parameter in fn.getEnvironment().getParams())
						observations.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "="
							+ parameter.getType().getDisplay());
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "arithmetic input facts differ:\n" + observations.join("\n");
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/arithmetic_operand_inference");
		observe(executable, [], expected);
		Sys.println("ARITHMETIC_INPUT_NATIVE:PASS");
	}
}
