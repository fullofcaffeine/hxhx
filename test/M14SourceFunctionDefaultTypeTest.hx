/** Preserve upstream callable and body types for full functions and arrows with defaults. */
class M14SourceFunctionDefaultTypeTest {
	/** Capture facts must keep the authored cell while distinguishing nullable call ingress. */
	static function checkCapturedEntry():Void {
		final source = "class Main { static function main():Void { function make(value:Int=5):Void->Int { value++; return () -> value; } } }";
		final module = TyperStage.typeModule(ParserStage.parse(source, "Main.hx"));
		final owner = module.getTypedClasses()[0].getFunctions()[0];
		final revision = CompilerTypedTreeRevision.functionBody(owner);
		final authored = TypedCapturePlan.analyze(owner);
		final bodyBinding = authored.getFunctions()[2].getCaptures()[0];
		final lowered = TypedControlLowering.functionBody(owner);
		final plan = TypedCapturePlan.afterLowering(owner, lowered);
		if (bodyBinding.getType().getSemanticKey() != "primitive:Int"
			|| plan.getFunctions()[2].getCaptures()[0].getCanonicalIdentity() != bodyBinding.getCanonicalIdentity())
			throw "default initialization replaced the escaping body binding";
		var incoming = 0;
		var declarations = 0;
		for (fact in plan.getBindings()) {
			if (fact.functionIdentity != plan.getFunctions()[1].identity)
				continue;
			if (fact.creation == FunctionEntry) {
				incoming++;
				if (fact.binding.getType().getSemanticKey() != "nullable:primitive:Int"
					|| fact.binding.getCanonicalIdentity() == bodyBinding.getCanonicalIdentity())
					throw "defaulted concrete parameter lost separate nullable ingress";
			}
			if (fact.binding.getCanonicalIdentity() == bodyBinding.getCanonicalIdentity()) {
				declarations++;
				if (fact.creation != Declaration)
					throw "body binding must be initialized after applying its default";
			}
		}
		if (incoming != 1 || declarations != 1 || revision != CompilerTypedTreeRevision.functionBody(owner))
			throw "default entry changed source identity or declaration ownership";
		if (plan.getCanonicalIdentity() != TypedCapturePlan.afterLowering(owner, TypedControlLowering.functionBody(lowered)).getCanonicalIdentity())
			throw "repeated default lowering changed capture ownership";
		final closure = plan.getFunctionExpressions()[0];
		final forged = new TyLocalBinding(TyLocalId.forCompilerTemporary(owner.getStableIdentity(), "unrelated-entry", 0, "value"), "value",
			TyType.nullable(bodyBinding.getType()), CompilerTemporary);
		for (invalid in [bodyBinding, forged]) {
			final replacement = TypedExpr.lambda(closure.getTexts(), closure.getExpressions()[0], closure.getType(), closure.getPosition(), [invalid],
				closure.getLambdaSignature());
			function replaceExpression(node:TypedExpr):TypedExpr
				return node == closure ? replacement : node.withExpressions([for (child in node.getExpressions()) replaceExpression(child)]);
			function replaceStatement(node:TypedStmt):TypedStmt
				return node.withChildren([for (child in node.getExpressions()) replaceExpression(child)],
					[for (child in node.getStatements()) replaceStatement(child)]);
			final changed = lowered.withBody(new TypedFunctionBody([for (node in lowered.getBody().getStatements()) replaceStatement(node)],
				lowered.getBody().getSourceFingerprint()));
			var diagnostic = "";
			try {
				TypedCapturePlan.afterLowering(owner, changed);
			} catch (error:String) {
				diagnostic = error;
			}
			if (diagnostic.indexOf("changed its parameter bindings") < 0)
				throw "capture validation admitted an unrelated or non-nullable entry binding: " + diagnostic;
		}
	}

	static function main():Void {
		for (entry in [
			{expression: "function(value=7) return value", expected: "primitive:Int"},
			{expression: "function(?value=7) return value", expected: "nullable:primitive:Int"},
			{expression: "(value=7) -> value", expected: "nullable:primitive:Int"},
			{expression: "function choose(value:Int=7):Int return value", expected: "primitive:Int"},
			{expression: "function(value:Int=7):Int return value", expected: "primitive:Int"},
			{expression: "function choose(?value:Int):Null<Int> return value", expected: "nullable:primitive:Int"},
			{expression: "function choose(?value:Int=7):Int return value", expected: "nullable:primitive:Int"},
			{expression: "function(value:Int=null):Null<Int> return value", expected: "nullable:primitive:Int"},
			{expression: "function(value:Null<Int>=7):Null<Int> return value", expected: "nullable:primitive:Int"},
			{expression: "(?value:Int) -> value", expected: "nullable:primitive:Int"},
			{expression: "(value:Int=7) -> value", expected: "nullable:primitive:Int"},
			{expression: "(value:Int=null) -> value", expected: "nullable:primitive:Int"}
		]) {
			final source = "class Main { static function main():Void { final read = " + entry.expression + "; } }";
			final module = TyperStage.typeModule(ParserStage.parse(source, "Main.hx"));
			final owner = module.getTypedClasses()[0].getFunctions()[0];
			final expression = owner.getBody().getStatements()[0].getExpressions()[0];
			final parameter = expression.getType().getFunctionParameters()[0];
			if (!parameter.isOptional || parameter.isRest || parameter.type.getSemanticKey() != entry.expected)
				throw "source callable parameter differs from upstream: " + entry.expression + " -> " + parameter.type.getSemanticKey();
			var found = false;
			for (binding in expression.getLocalBindings())
				if (binding.getSourceName() == "value") {
					found = true;
					if (binding.getType().getSemanticKey() != entry.expected)
						throw "source body parameter differs from upstream: " + entry.expression;
				}
			if (!found)
				throw "source function lost its body parameter binding";
			final revision = CompilerTypedTreeRevision.functionBody(owner);
			module.getBackendDeclaration();
			if (revision != CompilerTypedTreeRevision.functionBody(owner))
				throw "source default projection mutated the authored body";
		}
		checkCapturedEntry();
		Sys.println("SOURCE_FUNCTION_DEFAULT_TYPES:PASS");
	}
}
