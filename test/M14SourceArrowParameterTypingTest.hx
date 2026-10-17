/** Upstream typed macro observations require nullable optional/defaulted body parameters. */
class M14SourceArrowParameterTypingTest {
	static function main():Void {
		for (entry in [
			{parameter: "?value:Int", expected: "nullable:primitive:Int"},
			{parameter: "value:Int = 5", expected: "nullable:primitive:Int"},
			{parameter: "?value:String", expected: "nullable:primitive:String"},
			{parameter: "value:String = \"s\"", expected: "nullable:primitive:String"},
			{parameter: "?value:Null<Int>", expected: "nullable:primitive:Int"}
		]) {
			final source = "class Main { static function main():Void { final read = (" + entry.parameter + ") -> value; } }";
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final fn = typed.getTypedClasses()[0].getFunctions()[0];
			final expression = fn.getBody().getStatements()[0].getExpressions()[0];
			final signature = expression.getType();
			if (!signature.isFunction()
				|| signature.getFunctionArguments()[0].getSemanticKey() != entry.expected
				|| signature.getFunctionReturn().getSemanticKey() != entry.expected
				|| !signature.getFunctionParameters()[0].isOptional)
				throw "source parameter type differs from upstream: " + entry.parameter + " -> " + signature.getSemanticKey();
			final revision = CompilerTypedTreeRevision.functionBody(fn);
			typed.getBackendDeclaration();
			if (revision != CompilerTypedTreeRevision.functionBody(fn))
				throw "parameter entry lowering changed the authored typed tree";
		}
		Sys.println("SOURCE_ARROW_PARAMETER_TYPING:PASS");
	}
}
