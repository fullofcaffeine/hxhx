/** For bindings must preserve record fields and keep returns directed at the enclosing function. */
class M14SourceForTypingTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_for_return_seed/src", mainModule: "Main", requiredModules: ["Array", "Sys"]});
		final typed = fixture.main;
		for (fn in typed.getTypedClasses()[0].getFunctions()) {
			final once = TypedControlLowering.functionBody(fn);
			final revision = CompilerTypedTreeRevision.functionBody(once);
			final twice = TypedControlLowering.functionBody(once);
			if (CompilerTypedTreeRevision.functionBody(twice) != revision)
				throw "repeated control lowering changed range declarations or binding identities";
		}
		final statements = typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements();
		final callback = statements[1].getExpressions()[0];
		final loop = callback.getExpressions()[0].getExpressions()[0];
		if (loop.getTag() != SourceFor || loop.getControlTarget() == null || loop.getControlTarget().getKind() != Loop)
			throw "typed source for lost its exact loop destination";
		final bindings = loop.getLocalBindings();
		if (bindings.length != 1 || bindings[0].getType().hasUnknownComponent() || bindings[0].getType().isDynamic())
			throw "source for replaced the record element with an unresolved or dynamic local";
		final condition = loop.getExpressions()[1];
		final receiver = condition.getExpressions()[0].getExpressions()[0].getExpressions()[0];
		if (receiver.getTag() != LocalRead || receiver.getLocalBindings()[0].getCanonicalIdentity() != bindings[0].getCanonicalIdentity())
			throw "record field lookup did not use the exact loop-local binding";
		final returned = condition.getExpressions()[1];
		if (returned.getTag() != ReturnExpr || returned.getControlTarget() != callback.getControlTarget())
			throw "for body return was redirected from its authored function";
		switch TypedSourceSyntax.expression(loop) {
			case ESourceFor(Value("entry"), EIdent("entries"), ESourceIf(_, EReturn(EBool(true)), null, _), _):
			case _:
				throw "typed for did not project its original authored structure";
		}
		Sys.println("SOURCE_FOR_TYPING:PASS");
	}

	static function main():Void
		run();
}
