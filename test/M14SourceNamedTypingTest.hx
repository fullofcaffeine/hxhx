/** Named declarations and recursive reads share one finalized, immutable local identity. */
class M14SourceNamedTypingTest {
	static var declarations = 0;
	static var recursiveFunctions = 0;

	/** Haxe 4.3.7 makes function names read-only but permits writes to ordinary callable variables. */
	static function writeContracts():Void {
		final bodies = [
			"function recur(n:Int):Int { return n; } recur = function(n:Int):Int { return n + 1; };",
			"var callback = function recur(n:Int):Int { return n; }; recur = function(n:Int):Int { return n + 1; };",
			"function recur(n:Int):Int { recur = function(value:Int):Int { return value; }; return n; }"
		];
		for (body in bodies) {
			final source = "class Main { static function main():Void { " + body + " } }";
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			} catch (error:TyperError) {
				if (error.toString().indexOf("Cannot access function recur for writing") < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "named function write was accepted: " + body;
		}
		final source = "class Main { static function main():Void { function recur(n:Int):Int { return n; } var alias = recur; alias = function(n:Int):Int { return n + 1; }; { var recur = 1; recur = 2; } } }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function expression(node:TypedExpr):Void {
		if (node.getTag() == SourceFunction && node.getSourceFunction().getDeclaredName() != null) {
			final facts = node.getSourceFunction();
			final bindings = node.getLocalBindings();
			if (bindings.length != facts.getArguments().length + 1
				|| bindings[0].getSourceName() != facts.getDeclaredName()
				|| bindings[0].getKind() != NamedFunction
				|| bindings[0].getType().getSemanticKey() != node.getType().getSemanticKey())
				throw "named declaration did not retain its final callable binding before parameters";
			declarations++;
			final name = facts.getDeclaredName();
			if (name == "sum" || name == "count") {
				var found = false;
				function visit(child:TypedExpr):Void {
					if (child.getTag() == LocalRead && child.getTexts()[0] == name) {
						if (child.getLocalBindings()[0].getCanonicalIdentity() != bindings[0].getCanonicalIdentity())
							throw "recursive read differs from its declared function binding";
						found = true;
					}
					for (nested in child.getExpressions())
						visit(nested);
				}
				visit(node.getExpressions()[0]);
				if (!found)
					throw "recursive function lost its self-reference";
				recursiveFunctions++;
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

	public static function run():Void {
		writeContracts();
		declarations = 0;
		recursiveFunctions = 0;
		final path = "test/oracle/source_named_function_seed/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		for (fn in typed.getTypedClasses()[0].getFunctions()) {
			for (entry in fn.getBody().getStatements())
				statement(entry);
			final original = CompilerTypedTreeRevision.functionBody(fn);
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered))
				|| original != CompilerTypedTreeRevision.functionBody(fn))
				throw "named-function lowering changed a repeated or original typed revision";
		}
		if (declarations != 3 || recursiveFunctions != 2)
			throw "named fixture did not prove every declaration and recursive binding";
		Sys.println("SOURCE_NAMED_TYPING:PASS");
	}

	static function main():Void
		run();
}
