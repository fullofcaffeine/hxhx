import sys.io.File;

/** Bitwise body constraints must reach omitted parameters without narrowing written Dynamic inputs. */
class M14BitwiseParameterInferenceTest {
	static function main():Void {
		final root = "test/fixtures/bitwise_parameter_inference";
		final expected = File.getContent(root + "/expected.types");
		final oracle = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--macro", "UpstreamTypes.check()", "--no-output"]);
		final output = oracle.stdout.readAll().toString();
		final errors = oracle.stderr.readAll().toString();
		final code = oracle.exitCode();
		oracle.close();
		if (code != 0 || output != expected)
			throw "upstream bitwise parameter facts differ: " + output + errors;
		Sys.println("UPSTREAM_BITWISE_PARAMETERS:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final observed = new Array<String>();
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (parameter in fn.getEnvironment().getParams())
					observed.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "=" + parameter.getType().getDisplay());
		observed.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observed.join("\n") + "\n" != expected)
			throw "local bitwise parameter facts differ: " + observed.join(", ");
		Sys.println("BITWISE_PARAMETER_INFERENCE:PASS");
	}
}
