import sys.io.File;

/** Expected interfaces constrain concrete constructor variables without replacing their owner. */
class M14GenericConstructorNominalContextTest {
	static function main():Void {
		for (name in ["operand", "context", "reordered", "wrong_argument", "unrelated"])
			check(name);
		Sys.println("GENERIC_CONSTRUCTOR_NOMINAL_CONTEXT:PASS");
	}

	static function check(name:String):Void {
		final root = "test/fixtures/generic_constructor_nominal_context/" + name;
		final valid = name != "wrong_argument" && name != "unrelated";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (valid ? status != 0 || output != "value\n" : status == 0)
			throw "upstream constructor contract differs: " + name + output + errors;
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		var typed:TypedModule;
		try {
			typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			if (valid || error.message.indexOf("generic constructor conflicts with its expected type") < 0)
				throw error;
			Sys.println("CONSTRUCTOR_NOMINAL:" + name + ":PASS");
			return;
		}
		if (!valid)
			throw "invalid constructor context was accepted: " + name;
		final expected = name == "reordered" ? "nominal:Main.Cell<primitive:Int,primitive:String>" : "nominal:Main.Cell<primitive:String>";
		var allocations = 0;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == NewValue) {
				allocations++;
				if (node.getType().getSemanticKey() != expected)
					throw "constructor lost its concrete application: " + node.getType().getSemanticKey();
			}
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
		if (allocations != 1)
			throw "constructor fixture lost its allocation";
		JsRuntimeFixture.assertRuntime(typed, "Main", "value\n");
		Sys.println("CONSTRUCTOR_NOMINAL:" + name + ":PASS");
	}
}
