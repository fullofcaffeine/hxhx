import sys.io.File;

/** Structural methods retain their callable result and omission rules without a nominal method declaration. */
class M14StructuralCallableTest {
	static function type(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function main():Void {
		final source = File.getContent("test/fixtures/structural_callable/Main.hx");
		final root = ".tmp/structural_callable_upstream";
		sys.FileSystem.createDirectory(root);
		upstream(root, source, true);
		final typed = type(source);
		var calls = 0;
		function expression(node:TypedExpr):Void {
			final children = node.getExpressions();
			if (node.getTag() == Call && children.length > 0 && children[0].getTag() == FieldRead && children[0].getTexts()[0] == "choose") {
				calls++;
				final binding = node.getArgumentBinding();
				if (node.getDeclaration() != null || node.getType().getSemanticKey() != "primitive:Int" || binding == null)
					throw "structural call lost its checked function-value contract";
				final slots = binding.getSlots();
				if (slots.length != 2 || !slots[0].match(Omitted) || !slots[1].match(Supplied(0)))
					throw "structural call lost its optional argument mapping";
			}
			for (child in children)
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
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (calls != 2)
			throw "structural fixture lost a local or effectful receiver call";
		JsRuntimeFixture.assertRuntime(typed, "Main", "7\n8\n1\n");
		for (replacement in ["reader.choose()", "reader.choose(true)"]) {
			final invalid = StringTools.replace(source, "reader.choose(7)", replacement);
			upstream(root, invalid, false);
			var rejected = false;
			try
				type(invalid)
			catch (error:TyperError) {
				rejected = error.message.indexOf("Not enough arguments") >= 0 || error.message.indexOf("should be") >= 0;
			}
			if (!rejected)
				throw "invalid structural call was accepted: " + replacement;
		}
		Sys.println("STRUCTURAL_CALLABLE:PASS");
	}

	/** The installed upstream compiler independently checks both successful execution and invalid argument lists. */
	static function upstream(root:String, source:String, valid:Bool):Void {
		File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (valid ? status != 0 || output != "7\n8\n1\n" : status == 0)
			throw "upstream structural call contract differs: " + output + errors;
	}
}
