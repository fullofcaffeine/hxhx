import haxe.macro.Expr;

/** Public syntax observations shared by stock Haxe and the hxhx runtime parser test. */
class ComprehensionContract {
	public static function sources():Array<String> {
		return [
			"[for (item in values) item]",
			"[for (item in values) if (keep(item)) item]",
			"[for (item in values) (left => right)]",
			"[for (item in values) ((left => right))]",
			"[for (item in values) (\"a=>b\")]",
			"[for (item in values) (item /* => */)]",
			"[for (key => value in values) (key => value)]",
			"[for (outer in values) for (inner in outer) if (keep(inner)) ((inner))]"
		];
	}

	public static function expected():String {
		return [
			"array(for(OpIn(item,values),item))",
			"array(for(OpIn(item,values),if(call(keep,item),item,absent)))",
			"array(for(OpIn(item,values),paren(OpArrow(left,right))))",
			"array(for(OpIn(item,values),paren(paren(OpArrow(left,right)))))",
			"array(for(OpIn(item,values),paren(string:a=>b)))",
			"array(for(OpIn(item,values),paren(item)))",
			"array(for(OpArrow(key,OpIn(value,values)),paren(OpArrow(key,value))))",
			"array(for(OpIn(outer,values),for(OpIn(inner,outer),if(call(keep,inner),paren(paren(inner)),absent))))"
		].join("\n") + "\n";
	}

	/** Observe constructor identity, nesting, child order, and an absent else explicitly. */
	public static function shape(expression:Expr):String {
		return switch expression.expr {
			case EArrayDecl(values): "array(" + [for (value in values) shape(value)].join(",") + ")";
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case EBinop(operation, left, right): Std.string(operation) + "(" + shape(left) + "," + shape(right) + ")";
			case EFor(iterator, body): "for(" + shape(iterator) + "," + shape(body) + ")";
			case EIf(condition, yes, no): "if(" + shape(condition) + "," + shape(yes) + "," + (no == null ? "absent" : shape(no)) + ")";
			case EConst(CIdent(name)): name;
			case EConst(CString(text, _)): "string:" + text;
			case ECall(callee, arguments): "call(" + shape(callee) + "," + [for (argument in arguments) shape(argument)].join(",") + ")";
			case _: throw "unexpected comprehension syntax: " + Std.string(expression.expr);
		};
	}

	public static macro function observe():Expr {
		final actual = [
			for (source in sources())
				shape(haxe.macro.Context.parse(source, haxe.macro.Context.currentPos()))
		].join("\n") + "\n";
		if (actual != expected())
			throw "upstream comprehension syntax differs: " + actual;
		return macro $v{actual};
	}

	/** Ordinary loops and comprehensions use the same public binding constructor order. */
	public static macro function observeFor():Expr {
		final sources = ["for (value in values) value", "for (key => value in values) value"];
		final expected = "for(OpIn(value,values),value)\nfor(OpArrow(key,OpIn(value,values)),value)\n";
		final actual = [
			for (source in sources)
				shape(haxe.macro.Context.parse(source, haxe.macro.Context.currentPos()))
		].join("\n") + "\n";
		if (actual != expected)
			throw "upstream for binding syntax differs: " + actual;
		return macro $v{actual};
	}
}
