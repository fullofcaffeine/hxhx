/** Switch arms retain their blocks, declarations, loops, and abrupt exits before execution lowering. */
class M14SourceSwitchSyntaxTest {
	public static function run():Void {
		final source = HxParser.parseCompleteExprText("switch (1) { case 1: var value = 0; while (value < 2) { value++; continue; } value; default: 0; }");
		switch source {
			case ESwitch(EParenthesized(EInt(1), _), [PInt(1), PWildcard], [
				ESourceGroup([EVars(_), EWhile(_, [_, EContinue(_)], true, _, loopKind), EIdent("value")], _),
				ESourceGroup([EInt(0)], _)
			]):
			case _:
				throw "switch arms changed their independently verified upstream block structure";
		}
		TypedBackendSourceWalk.expression(source, expression -> switch expression {
			case ELambda(_, _, _) | EReturn(_): throw "switch parsing inserted a function or return";
			case _:
		});
		final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(source, []), HxPos.unknown(), null).getExpressions()[0];
		final nested = HxParser.parseCompleteExprText("switch (1) { case 1: switch (2) { case 2: 3; default: 0; } default: 0; }");
		switch nested {
			case ESwitch(_, _, [ESourceGroup([ESwitch(_, [PInt(2), PWildcard], _)], _), _]):
			case _:
				throw "nested switch inherited its enclosing arm's case delimiter";
		}
		final initialized = HxParser.parseCompleteExprText('switch (1) { default: final selected = if (true) { "ok"; } else { "wrong"; } selected; }');
		switch initialized {
			case ESwitch(_, _, [ESourceGroup([EVars(_), EIdent("selected")], _)]):
			case _:
				throw "braced initializer consumed the following switch-arm expression";
		}
		if (TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(quoted)) != TypedBodyFingerprint.forExpression(source))
			throw "quoted switch lost authored arm syntax";
		for (malformed in ["switch (1) case 1: 2;", "switch (1) { case 1: 2;", "switch (1) { unexpected; }"]) {
			var rejected = false;
			try {
				HxParser.parseCompleteExprText(malformed);
			} catch (_:HxParseError) {
				rejected = true;
			}
			if (!rejected)
				throw "malformed switch expression was accepted: " + malformed;
		}
		Sys.println("SOURCE_SWITCH_SYNTAX:PASS");
	}

	static function main():Void
		run();
}
