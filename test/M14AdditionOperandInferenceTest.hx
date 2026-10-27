import sys.io.File;

/** Compare independently specified parameter facts and a real native callback invocation. */
class M14AdditionOperandInferenceTest {
	static final root = "test/fixtures/addition_operand_inference";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "addition inference observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		rejectIncompatibleInputs();
		final expectedTypes = File.getContent(root + "/expected.types");
		observe("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/method_parameter_dynamic_context",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"UpstreamTypes.check()",
			"--no-output"
		], expectedTypes);
		final expected = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("ADDITION_INPUT_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final observations:Array<String> = [];
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (parameter in fn.getEnvironment().getParams())
					observations.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "=" + parameter.getType().getDisplay());
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "addition input facts differ: " + observations.join(", ");
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/addition_operand_inference");
		observe(executable, [], expected);
		Sys.println("ADDITION_INPUT_NATIVE:PASS");
	}

	/** Body-derived inputs reject incompatible calls with a typing diagnostic, before target emission. */
	static function rejectIncompatibleInputs():Void {
		for (argument in ["true", "1.5", '"bad"']) {
			final directory = ".tmp/addition_operand_rejected";
			sys.FileSystem.createDirectory(directory);
			final path = directory + "/Main.hx";
			final source = "class Main { static function run(value):Int return value + 1; static function main() { run(" + argument + "); } }";
			File.saveContent(path, source);
			final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
				["30", "node_modules/.bin/haxe", "-cp", directory, "-main", "Main", "--no-output"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 1 || stderr.indexOf("should be Int") < 0)
				throw "upstream failed to reject incompatible addition input: " + stdout + stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (error:TyperError) {
				rejected = error.getMessage().indexOf("No compatible method signature for run") >= 0;
			}
			if (!rejected)
				throw "candidate accepted an incompatible addition input";
		}
		Sys.println("ADDITION_INPUT_DIAGNOSTICS:PASS");
	}
}
