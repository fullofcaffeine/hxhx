/** Check allocation field types separately from the source types of their children. */
class M14ContextualRecordTypingTest {
	static function typeSource(source:String):TypedModule {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function main():Void {
		final typed = typeSource(sys.io.File.getContent("test/oracle/contextual_record_seed/Main.hx"));
		var literals = 0;
		var location = "";
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Anonymous) {
				literals++;
				final names = value.getType().getAnonymousFieldNames();
				if (names.indexOf("absent") >= 0)
					throw "optional field absence became an allocated field";
				final index = names.indexOf("item");
				if (index >= 0) {
					final expected = location == "inferred" ? "primitive:Bool" : "dynamic";
					if (value.getType().getAnonymousFieldTypes()[index].getSemanticKey() != expected)
						throw "literal lost field context in " + location;
					final child = value.getExpressions()[0];
					if (!child.getType().isNullLiteral() && child.getType().getSemanticKey() != "primitive:Bool")
						throw "field context erased the authored child type in " + location;
				}
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions()) {
				location = HxFunctionDecl.getName(method.getSourceDeclaration());
				for (child in method.getBody().getStatements())
					statement(child);
			}
		if (literals != 9)
			throw "contextual record fixture lost a literal: " + literals;
		for (invalid in [
			"final value:{item:Int} = {item: true};",
			"final value:{item:Int} = {item: 1, extra: true};",
			"final value:{item:Int, other:String} = {item: 1};"
		]) {
			var rejected = false;
			try {
				typeSource("class Main { static function main():Void { " + invalid + " } }");
			} catch (_:TyperError) {
				rejected = true;
			}
			if (!rejected)
				throw "invalid contextual record was accepted: " + invalid;
		}
		Sys.println("CONTEXTUAL_RECORD_TYPING:PASS");
	}
}
