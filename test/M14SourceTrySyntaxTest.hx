import haxe.macro.Expr;

using StringTools;

/** Try syntax must expose the original bodies and ordered annotations to macros. */
class M14SourceTrySyntaxTest {
	static function convert(source:HxExpr):Expr {
		final mapped = HxSourceMacroSyntax.definition(source, convert, name -> TPath({pack: [], name: name}));
		final definition:ExprDef = mapped != null ? mapped : switch source {
			case EInt(value): EConst(CInt(Std.string(value)));
			case EIdent(name): EConst(CIdent(name));
			case EReturn(value): EReturn(value == null ? null : convert(value));
			case _: throw "unexpected source-try syntax fixture leaf";
		};
		return {expr: definition, pos: null};
	}

	public static function run():Void {
		final text = "try { 1; } catch (number:Int) { 2; } catch (text:String) { 3; }";
		final source = HxParser.parseCompleteExprText(text);
		final catches = switch source {
			case ESourceTry(catches, [ESourceGroup([EInt(1)], _), ESourceGroup([EInt(2)], _), ESourceGroup([EInt(3)], _)], _): catches;
			case _: throw "try parser changed original lexical bodies";
		};
		if (catches.length != 2 || catches[0].getName() != "number" || catches[0].getTypeHint() != "Int" || catches[1].getName() != "text"
			|| catches[1].getTypeHint() != "String")
			throw "try parser changed ordered catch declarations";
		if (catches[0].getPosition().getIndex() != text.indexOf("catch (number")
			|| catches[1].getPosition().getIndex() != text.indexOf("catch (text"))
			throw "catch start positions no longer identify the original source";
		switch convert(source).expr {
			case ETry({expr: EBlock([{expr: EConst(CInt("1"))}])}, [
				{name: "number", type: TPath({name: "Int"}), expr: {expr: EBlock([{expr: EConst(CInt("2"))}])}},
				{name: "text", type: TPath({name: "String"}), expr: {expr: EBlock([{expr: EConst(CInt("3"))}])}}
			]):
			case _:
				throw "public macro syntax lost ordered try handlers";
		}
		final omitted = HxParser.parseCompleteExprText("try 1 catch (error) 2");
		switch convert(omitted).expr {
			case ETry(_, [{name: "error", type: null}]):
			case _:
				throw "omitted catch annotation became written syntax";
		}
		final quote = TypedBodyBuilder.buildExpression(EMacroExpr(source, []), HxPos.unknown(), null).getExpressions()[0];
		if (quote.getTag() != SourceTry || quote.getLocalBindings().length != 0 || quote.getControlTarget() != null)
			throw "quoted try acquired executing catch bindings";
		if (TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(quote)) != TypedBodyFingerprint.forExpression(source))
			throw "try quote round trip changed authored facts";
		final revision = CompilerTypedTreeRevision.expression("quote", quote);
		for (copy in [
			quote.withExpressions(quote.getExpressions()),
			quote.withType(quote.getType()),
			quote.withCatchUses([])
		])
			if (CompilerTypedTreeRevision.expression("quote", copy) != revision)
				throw "typed rebuild lost source catch facts";
		final exposed = quote.getSourceCatches();
		exposed.pop();
		if (quote.getSourceCatches().length != 2)
			throw "catch accessor exposed mutable ordered storage";
		for (variant in [
			text.replace("number:Int", "number:String"),
			text.replace("number:Int", "other:Int"),
			" " + text
		]) {
			final changed = TypedBodyBuilder.buildExpression(EMacroExpr(HxParser.parseCompleteExprText(variant), []), HxPos.unknown(), null)
				.getExpressions()[0];
			if (CompilerTypedTreeRevision.expression("quote", changed) == revision)
				throw "catch name, annotation, or position failed to invalidate typed identity";
		}
		for (malformed in ["try 1", "try 1 catch () 2", "try 1 catch (error:) 2", "try 1 catch (error:Int)"]) {
			var rejected = false;
			try
				HxParser.parseCompleteExprText(malformed)
			catch (_:HxParseError)
				rejected = true;
			if (!rejected)
				throw "malformed try was accepted: " + malformed;
		}
		Sys.println("SOURCE_TRY_SYNTAX:PASS");
	}

	static function main():Void
		run();
}
