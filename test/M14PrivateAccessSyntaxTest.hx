import haxe.macro.Expr;

/** Upstream-observed metadata scope and exact source identity survive typed quotation. */
class M14PrivateAccessSyntaxTest {
	static function convert(source:HxExpr):Expr {
		final mapped = HxSourceMacroSyntax.definition(source, convert, _ -> null);
		final definition:ExprDef = mapped != null ? mapped : switch source {
			case EIdent(name): EConst(CIdent(name));
			case EUnop(op, fixity, inner):
				EUnop(op == Increment ? OpIncrement : OpDecrement, fixity == Postfix, convert(inner));
			case ETernary(condition, whenTrue, whenFalse): ETernary(convert(condition), convert(whenTrue), convert(whenFalse));
			case _: throw "unexpected privateAccess probe source";
		};
		return {expr: definition, pos: null};
	}

	static function shape(value:Expr):String {
		return switch value.expr {
			case EMeta(metadata, inner): "meta(" + metadata.name + "," + shape(inner) + ")";
			case EBinop(op, left, right): Std.string(op) + "(" + shape(left) + "," + shape(right) + ")";
			case EConst(CIdent(name)): name;
			case ETernary(condition, whenTrue, whenFalse): "ternary("
				+ shape(condition)
				+ ","
				+ shape(whenTrue)
				+ ","
				+ shape(whenFalse)
				+ ")";
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case EUnop(op, postfix, inner): Std.string(op) + "(" + postfix + "," + shape(inner) + ")";
			case _: throw "unexpected privateAccess macro shape";
		};
	}

	static function main():Void {
		// These trees were observed through Haxe 4.3.7 Context.parse, separately
		// from this parser and its typed-to-source reconstruction.
		final cases = [
			{source: "@:privateAccess a = b + c", expected: "meta(:privateAccess,OpAssign(a,OpAdd(b,c)))"},
			{source: "@:privateAccess a + b", expected: "OpAdd(meta(:privateAccess,a),b)"},
			{source: "@:privateAccess @:privateAccess a = b ? c : d", expected: "meta(:privateAccess,meta(:privateAccess,OpAssign(a,ternary(b,c,d))))"},
			{source: "++@:privateAccess a", expected: "OpIncrement(false,meta(:privateAccess,a))"},
			{source: "@:privateAccess a++", expected: "meta(:privateAccess,OpIncrement(true,a))"},
			{source: "(@:privateAccess a) = b", expected: "OpAssign(paren(meta(:privateAccess,a)),b)"}
		];
		for (entry in cases) {
			final parsed = HxParser.parseCompleteExprText(entry.source);
			if (shape(hxhxmacrohost.api.RuntimeMacroExprs.parse(entry.source, null)) != entry.expected)
				throw "runtime macro parser changed privateAccess scope";
			if (shape(convert(parsed)) != entry.expected)
				throw "privateAccess parse scope differs: " + entry.source;
			final quote = TypedBodyBuilder.buildExpression(EMacroExpr(parsed, []), HxPos.unknown(), null);
			final child = quote.getExpressions()[0];
			final restored = TypedSourceSyntax.expression(child);
			if (shape(convert(restored)) != entry.expected
				|| TypedBodyFingerprint.exactExpression(parsed) != TypedBodyFingerprint.exactExpression(restored))
				throw "privateAccess quote lost source structure or position";
		}
		final parsed = HxParser.parseCompleteExprText("  @:privateAccess a");
		final typed = TypedBodyBuilder.buildExpression(EMacroExpr(parsed, []), HxPos.unknown(), null).getExpressions()[0];
		if (typed.getTag() != PrivateAccess || typed.getPosition().getIndex() != 2)
			throw "privateAccess lost its exact authored position";
		final inner = typed.getExpressions()[0];
		if (CompilerTypedTreeRevision.expression("permission", typed) == CompilerTypedTreeRevision.expression("permission", inner))
			throw "typed revision ignored the permission";
		if (TypedBodyFingerprint.exactExpression(parsed) == TypedBodyFingerprint.exactExpression(EIdent("a")))
			throw "source identity ignored the permission";
		var rejected = false;
		try {
			TypedBodySource.expression(typed);
		} catch (error:String) {
			rejected = error.indexOf("access permission") >= 0;
		}
		if (!rejected)
			throw "backend projection accepted unresolved source permission";
		Sys.println("PRIVATE_ACCESS_SYNTAX:PASS");
	}
}
