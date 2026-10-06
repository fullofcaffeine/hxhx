import sys.io.File;

/** Expression switches must retain postfix operations just as statement switches do. */
class M14SwitchExpressionSuffixTest {
	static function main():Void {
		final root = "test/fixtures/switch_expression_suffix";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "zero\nother\n")
			throw "upstream switch suffix contract differs: " + stdout + stderr;
		final shapes = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node_modules/.bin/haxe", "-cp", root, "--run", "Shapes"]);
		final shapeOutput = shapes.stdout.readAll().toString();
		final shapeErrors = shapes.stderr.readAll().toString();
		final shapeStatus = shapes.exitCode();
		shapes.close();
		if (shapeStatus != 0 || shapeOutput != "paren(values)\nparen(paren(values))\nindex(paren(values),0)\n")
			throw "upstream switch operand grouping differs: " + shapeOutput + shapeErrors;
		for (source in ["switch (values) { default: 0; }", "switch ((values)) { default: 0; }"]) {
			final parsed = HxParser.parseCompleteExprText(source);
			switch parsed {
				case ESwitch(EParenthesized(inner, _), _, _):
					switch inner {
						case EIdent("values") if (source.indexOf("((") == -1):
						case EParenthesized(EIdent("values"), _) if (source.indexOf("((") >= 0):
						case _: throw "switch changed its nested operand parentheses";
					}
				case _:
					throw "switch discarded authored operand parentheses";
			}
		}
		final expression = HxParser.parseCompleteExprText("switch (untyped holder.values)[index] { case null: null; case item: item.name; }");
		switch expression {
			case ESwitch(EArrayAccess(EParenthesized(EUntyped(EField(EIdent("holder"), "values")), _), EIdent("index")), _, _):
			case _:
				throw "switch expression lost its exact parenthesized/indexed operand";
		}
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		M14GenericConstructorArgumentTest.assertRuntime(typed, "Main", "zero\nother\n");
		Sys.println("SWITCH_EXPRESSION_SUFFIX:PASS");
	}
}
