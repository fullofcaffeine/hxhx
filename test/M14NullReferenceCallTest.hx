import sys.io.File;

/** Check declaration selection before target emission can hide a missing call owner. */
class M14NullReferenceCallTest {
	static final failures:Array<String> = [];
	static var observed:Int = 0;

	static function expression(node:TypedExpr):Void {
		if (node.getTag() == Call) {
			final children = node.getExpressions();
			if (children.length == 2 && children[0].getTag() == NameRead && children[1].getTag() == NullValue) {
				observed++;
				if (node.getDeclaration() == null)
					failures.push(children[0].getTexts().join("."));
				else if (node.getDeclaration().getSignature().getName() != children[0].getTexts()[0])
					throw "Null reference call selected a different method";
			}
		}
		for (child in node.getExpressions())
			expression(child);
	}

	static function statement(node:TypedStmt):Void {
		for (value in node.getExpressions())
			expression(value);
		for (child in node.getStatements())
			statement(child);
	}

	static function main():Void {
		final path = "test/fixtures/null_reference_call/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		for (type in typed.getTypedClasses())
			for (fn in type.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (observed != 4)
			throw "Expected four null reference calls, found " + observed;
		if (failures.length != 0)
			throw "Null reference calls lost declarations: " + failures.join(", ");
		observe("haxe", ["-cp", "test/fixtures/null_reference_call", "--run", "Main"]);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/null-reference-call", true);
		observe(executable, []);
		Sys.println("M14_NULL_REFERENCE_CALL:PASS");
	}

	/** Observe real target execution, not only the presence of a declaration. */
	static function observe(command:String, arguments:Array<String>):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "true\ntrue\ntrue\ntrue\nfalse\n")
			throw "Null reference observer failed: " + command + ": " + stdout + stderr;
	}
}
