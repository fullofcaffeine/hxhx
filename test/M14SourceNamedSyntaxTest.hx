/** Named functions preserve names, inline flags, written defaults, and source placement for macros. */
class M14SourceNamedSyntaxTest {
	public static function run():Void {
		final source = HxParser.parseCompleteExprText('{ function named(value:Int):Int { return value; } inline function fast(value:Int):Int { return value; } final callback = function recur(value:Int = 2):Int { return value; }; }');
		switch source {
			case ESourceGroup([
				ESourceFunction(named, _, _, _),
				ESourceFunction(fast, _, _, _),
				EVars([declaration])
			], _):
				if (!named.getKind().match(Named("named", false)) || named.getPlacement() != Declaration)
					throw "named declaration lost its source kind or placement";
				if (!fast.getKind().match(Named("fast", true)) || fast.getPlacement() != Declaration)
					throw "inline declaration lost its source flag";
				switch HxExprVarDecl.getInitializer(declaration) {
					case ESourceFunction(facts, _, [EInt(2)], _):
						final parameter = facts.getSignature().getParameters()[0];
						if (!facts.getKind().match(Named("recur", false))
							|| facts.getPlacement() != Value
							|| parameter.isOptional
							|| !parameter.hasDefault) throw "named value or its default changed source facts";
					case _: throw "named function default became a parameter-read rewrite";
				}
			case _:
				throw "named functions were replaced by variable or lambda transport";
		}
		final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(source, []), HxPos.unknown(), null).getExpressions()[0];
		if (TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(quoted)) != TypedBodyFingerprint.forExpression(source))
			throw "quoted named functions changed authored structure";
		Sys.println("SOURCE_NAMED_SYNTAX:PASS");
	}

	static function main():Void
		run();
}
