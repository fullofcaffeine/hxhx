import sys.io.File;

/** Checked body inputs specialize constructor calls without changing their immutable declaration headers. */
class M14ConstructorBodyInputsTest {
	static function main():Void {
		final root = "test/fixtures/constructor_body_inputs";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
		Sys.println("CONSTRUCTOR_BODY_INPUTS:upstream:PASS");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final module = TyperStage.typeResolvedModule(resolved, index);
		var allocations = 0;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == NewValue) {
				final application = node.getConstructorApplication();
				if (application == null || node.getDeclaration() != application.getDeclaration())
					throw "allocation lost its exact inferred constructor";
				final declaration = application.getDeclaration();
				final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
				if (owner.declarationForSignature(declaration.getSignature()) != declaration)
					throw "constructor inference replaced its declaration";
				if (declaration.getSignature().getArgs().filter(type -> type.isUnknown()).length != 5)
					throw "body inference rewrote constructor headers";
				final parameters = application.getParameterTypes();
				final expected = allocations == 1 ? ["Int", "String"] : ["String", "Int"];
				if (parameters.length != 5
					|| parameters.filter(type -> type.hasUnknownComponent()).length != 0
					|| parameters[1].getSemanticKey() != TyType.fromHintText(expected[0]).getSemanticKey()
					|| parameters[2].getSemanticKey() != TyType.fromHintText(expected[1]).getSemanticKey()
					|| parameters[4].getSemanticKey() != TyType.fromHintText("Int").getSemanticKey())
					throw "constructor application lost checked input types";
				final sources = node.getExpressions().map(TypedSourceSyntax.expression);
				final types = node.getExpressions().map(value -> value.getType());
				function rejected(arguments:Array<HxExpr>, actual:Array<TyType>):Void {
					final selected = TypedConstructorSelection.select(index, application.getConstructedType(), actual, arguments,
						(signature, supplied,
								binders) -> @:privateAccess TyperStage.overloadCandidateScore(signature, supplied, supplied.length, binders, index));
					if (selected != null)
						throw "checked constructor inputs admitted an incompatible call";
				}
				final wrongSources = sources.copy();
				final wrongTypes = types.copy();
				wrongSources[1] = expected[0] == "String" ? EInt(8) : EString("wrong");
				wrongTypes[1] = TyType.fromHintText(expected[0] == "String" ? "Int" : "String");
				rejected(wrongSources, wrongTypes);
				rejected(sources.slice(0, 3), types.slice(0, 3));
				allocations++;
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
		final entries = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main")
						fn
		];
		if (entries.length != 1)
			throw "constructor fixture requires one entry point";
		for (body in entries[0].getBody().getStatements())
			statement(body);
		if (allocations != 3)
			throw "constructor allocation inventory differs";
		final program = new MacroExpandedProgram([module], false);
		final reachable = TypedFeatureMemberClosure.retain({
			program: program,
			classes: [],
			functions: entries,
			fields: []
		});
		final retained = new TypedEmissionRetention({reachable: reachable, mode: "full"}).apply(program);
		JsRuntimeFixture.assertRuntime(retained.getTypedModules()[0], "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("CONSTRUCTOR_BODY_INPUTS:PASS");
	}
}
