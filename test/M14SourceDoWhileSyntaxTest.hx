import haxe.macro.Expr;

/** Loop order is source syntax and must survive quotation, rebuilding, and revision checks. */
class M14SourceDoWhileSyntaxTest {
	static function convert(source:HxExpr):Expr {
		final mapped = HxSourceMacroSyntax.definition(source, convert, _ -> null);
		final definition:ExprDef = mapped != null ? mapped : switch source {
			case EIdent(name): EConst(CIdent(name));
			case _: throw "unexpected loop syntax fixture leaf";
		};
		return {expr: definition, pos: null};
	}

	public static function run():Void {
		final source = HxParser.parseCompleteExprText("do { body; } while (condition)");
		switch source {
			case HxExpr.EWhile(EIdent("condition"), [EIdent("body")], true, position, DoWhile):
				if (position.getIndex() != 0)
					throw "do loop lost its start position";
			case _:
				throw "do loop became a helper or lost its original body";
		}
		switch convert(source).expr {
			case EWhile({expr: EConst(CIdent("condition"))}, {expr: EBlock([{expr: EConst(CIdent("body"))}])}, false):
			case _:
				throw "macro conversion lost body-before-condition order";
		}
		final quote = TypedBodyBuilder.buildExpression(EMacroExpr(source, []), HxPos.unknown(), null).getExpressions()[0];
		if (quote.getWhileKind() != DoWhile || quote.getControlTarget() != null)
			throw "quoted do loop changed kind or acquired an executing destination";
		final revision = CompilerTypedTreeRevision.expression("quote", quote);
		for (copy in [
			quote.withExpressions(quote.getExpressions()),
			quote.withType(quote.getType()),
			quote.withCatchUses([])
		]) {
			if (copy.getWhileKind() != DoWhile || CompilerTypedTreeRevision.expression("quote", copy) != revision)
				throw "typed rebuild lost loop order";
			if (TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(copy)) != TypedBodyFingerprint.forExpression(source))
				throw "do loop source round trip changed";
		}
		final normal = TypedExpr.whileExpr(quote.getExpressions()[0], quote.getExpressions().slice(1), quote.getBoolValue(), quote.getType(),
			quote.getPosition(), Normal);
		if (CompilerTypedTreeRevision.expression("quote", normal) == revision
			|| TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(normal)) == TypedBodyFingerprint.forExpression(source))
			throw "loop order failed to invalidate typed or source identity";
		for (malformed in [
			"do",
			"do {}",
			"do {} while",
			"do {} while ()",
			"do {} while (condition",
			"do body; while (condition)",
			"do {}; while (condition)"
		]) {
			var rejected = false;
			try
				HxParser.parseCompleteExprText(malformed)
			catch (_:HxParseError)
				rejected = true;
			if (!rejected)
				throw "malformed do loop was accepted: " + malformed;
		}
		switch HxParser.parseCompleteExprText("do body while (condition)") {
			case HxExpr.EWhile(EIdent("condition"), [EIdent("body")], false, _, DoWhile):
			case _:
				throw "single-expression do body changed shape";
		}
		Sys.println("SOURCE_DO_WHILE_SYNTAX:PASS");
	}

	static function main():Void
		run();
}
