import haxe.macro.Expr;

/** Parentheses retain nested source grouping without creating a callable or control owner. */
class M14SourceParenthesizedSyntaxTest {
	static function convert(source:HxExpr):Expr {
		final mapped = HxSourceMacroSyntax.definition(source, convert, _ -> null);
		final definition:ExprDef = mapped != null ? mapped : switch source {
			case EIdent(name): EConst(CIdent(name));
			case EInt(value): EConst(CInt(Std.string(value), null));
			case EBinop(op, left, right):
				final operation:Binop = switch op {
					case "=": OpAssign;
					case "+": OpAdd;
					case "*": OpMult;
					case _: throw "unexpected probe operator";
				};
				EBinop(operation, convert(left), convert(right));
			case ECall(callee, arguments): ECall(convert(callee), [for (argument in arguments) convert(argument)]);
			case _: throw "unexpected parenthesis probe source";
		};
		return {expr: definition, pos: null};
	}

	static function shape(expression:Expr):String {
		return switch expression.expr {
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case EConst(CIdent(name)): name;
			case EConst(CInt(value, _)): value;
			case EBinop(OpAssign, left, right): "assign(" + shape(left) + "," + shape(right) + ")";
			case EBinop(OpAdd, left, right): "add(" + shape(left) + "," + shape(right) + ")";
			case EBinop(OpMult, left, right): "mul(" + shape(left) + "," + shape(right) + ")";
			case ECall(callee, arguments): "call(" + shape(callee) + "," + [for (argument in arguments) shape(argument)].join(",") + ")";
			case _: throw "unexpected parenthesis probe macro shape";
		};
	}

	public static function run():Void {
		final cases = ["((value))", "(value = 3)", "((value = 3))", "(1 + 2) * 3", "(value) = 4"];
		final expected = sys.io.File.getContent("test/oracle/source_parenthesized_seed/syntax.stdout");
		final actual = [for (source in cases) shape(convert(HxParser.parseCompleteExprText(source)))].join("\n") + "\n";
		if (actual != expected)
			throw "parenthesized macro shapes differ: " + actual;
		for (source in cases) {
			final parsed = HxParser.parseCompleteExprText(source);
			final typed = TypedBodyBuilder.buildExpression(EMacroExpr(parsed, []), HxPos.unknown(), null).getExpressions()[0];
			final rebuilt = TypedSourceSyntax.expression(typed);
			if (shape(convert(rebuilt)) != shape(convert(parsed)))
				throw "typed quote changed parentheses";
			if (TypedBodyFingerprint.forExpression(rebuilt) != TypedBodyFingerprint.forExpression(parsed))
				throw "typed quote changed source identity";
			if (CompilerTypedTreeRevision.expression("quote",
				typed) != CompilerTypedTreeRevision.expression("quote", typed.withExpressions(typed.getExpressions())))
				throw "typed rebuild changed parenthesized identity";
		}
		switch HxParser.parseCompleteExprText("macro ((value = 3))") {
			case EMacroExpr(quoted, wrappers):
				if (wrappers.length != 0 || shape(convert(quoted)) != "paren(paren(assign(value,3)))")
					throw "macro quote retained a separate parenthesis wrapper route";
			case _:
				throw "expected a source expression quote";
		}
		for (write in [
			"(value) = 4",
			"((value)) = 4",
			"(value) += 4",
			"(value) ??= 4",
			"++(value)",
			"(value)++"
		]) {
			final source = "class Main { static function main() { var value = 1; " + write + "; } }";
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			} catch (error:haxe.Exception) {
				rejected = error.message.indexOf("Invalid assign") >= 0;
			}
			if (!rejected)
				throw "parenthesized write was admitted: " + write;
		}
		Sys.println("SOURCE_PARENTHESIZED_SYNTAX:PASS");
	}

	static function main():Void
		run();
}
