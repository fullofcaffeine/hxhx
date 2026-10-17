import sys.io.File;

/** Compare authored metadata expressions with upstream before checking typed ownership. */
class M14ExpressionMetadataTest {
	static function main():Void {
		quoteContract();
		final root = "test/fixtures/expression_metadata";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("EXPRESSION_METADATA_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var preciseLocals = 0;
		function inspect(statement:TypedStmt):Void {
			for (binding in statement.getLocalBindings())
				if (binding.getSourceName() == "first" || binding.getSourceName() == "second") {
					if (binding.getType().getSemanticKey() != "primitive:Int")
						throw "metadata erased the inferred value type";
					preciseLocals++;
				}
			for (child in statement.getStatements())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					inspect(statement);
		if (preciseLocals != 2)
			throw "metadata fixture lost its typed locals";
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("EXPRESSION_METADATA_RUNTIME:PASS");
	}

	/** Quotation keeps names, arguments, nesting, and revision identity until a macro consumes them. */
	static function quoteContract():Void {
		final text = '@:probe("kept") @:nested 7';
		final source = HxParser.parseCompleteExprText(text);
		final quote = TypedBodyBuilder.buildExpression(EMacroExpr(source, []), HxPos.unknown(), null);
		final value = quote.getExpressions()[0];
		if (value.getTag() != Metadata || value.getExpressions()[0].getTag() != Metadata)
			throw "metadata quote lost its nested typed wrappers";
		if (TypedBodyFingerprint.exactExpression(TypedSourceSyntax.expression(value)) != TypedBodyFingerprint.exactExpression(source))
			throw "metadata quote changed authored syntax";
		final revision = CompilerTypedTreeRevision.expression("metadata", value);
		for (variant in ['@:other("kept") @:nested 7', '@:probe("changed") @:nested 7']) {
			final altered = TypedBodyBuilder.buildExpression(EMacroExpr(HxParser.parseCompleteExprText(variant), []), HxPos.unknown(), null)
				.getExpressions()[0];
			if (CompilerTypedTreeRevision.expression("metadata", altered) == revision)
				throw "metadata change did not invalidate typed revision";
		}
		Sys.println("EXPRESSION_METADATA_QUOTE:PASS");
	}
}
