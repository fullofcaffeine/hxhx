import sys.io.File;

/** Omitted constructor arguments must be solved before exact call and capture publication. */
class M14GenericConstructorContextTest {
	static function main():Void {
		check("Main", "expected.stdout", ["String", "String"]);
		check("IdentityCases", "identity.expected.stdout", ["String", "String", "String", "String", "Int", "Int"]);
		check("MemberCases", "member.expected.stdout", ["String", "Int", "Float"]);
		Sys.println("GENERIC_CONSTRUCTOR_CONTEXT:PASS");
	}

	/** Compare independent upstream behavior with every recursively published constructor type. */
	static function check(module:String, expectedOutput:String, expectedArguments:Array<String>):Void {
		final root = "test/fixtures/generic_constructor_context";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", "node_modules/.bin/haxe", "-cp", root, "--run", module]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != File.getContent(root + "/" + expectedOutput))
			throw "upstream generic constructor context failed: " + stdout + stderr;
		final path = root + "/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final actual = new Array<String>();
		final memberResults = new Array<String>();
		function expression(node:TypedExpr):Void {
			if (node.getTag() == NewValue)
				actual.push(node.getType().getSemanticKey());
			if (node.getTag() == Call && node.getDeclaration() != null && node.getDeclaration().getSignature().getName() == "get")
				memberResults.push(node.getType().getSemanticKey());
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (node in fn.getBody().getStatements())
					statement(node);
		final expected = [
			for (argument in expectedArguments)
				"nominal:" + module + ".Box<primitive:" + argument + ">"
		];
		actual.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		expected.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (actual.join("\n") != expected.join("\n"))
			throw module + " constructor contexts differ: " + actual.join("; ");
		if (module == "MemberCases"
			&& memberResults.join(";") != "nullable:primitive:String;nullable:primitive:Int;nullable:primitive:Float")
			throw "generic member results lost the receiver arguments: " + memberResults.join(";");
		for (owner in typed.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				fn.requireCaptureCatalog();
		Sys.println(module + ":PASS");
	}
}
