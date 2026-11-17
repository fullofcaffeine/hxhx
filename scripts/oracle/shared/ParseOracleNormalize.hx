import haxe.macro.Expr;

/**
	Spellings that the frontend parse oracle treats as equal, applied to both sides before printing.

	Only differences that cannot change meaning are removed:
	- Quote style: `'a'` and `"a"` print the same. A single-quoted string that contains `$` keeps
	  its quotes, because Haxe interpolates it; such a string is not equal to a double-quoted one.
	- Number spelling: `0xFF` and `255`, or `1.0` and `1`, print as the same decimal value. A
	  suffix such as `i64` is kept.
	- Switch fallbacks: `default:` and `case _:` print as `case _:`.
	- Case lists: `case A, B:` prints as `case A | B:`.
	- Captures: `case var t:` prints as `case t:`.
	- Empty case bodies: `case A:` and `case A: {}` print the same.
**/
class ParseOracleNormalize {
	public static function expr(e:Null<Expr>):Null<Expr> {
		if (e == null || e.expr == null)
			return e;
		return switch e.expr {
			case EConst(CString(value, SingleQuotes)) if (value.indexOf("$") < 0):
				{expr: EConst(CString(value, DoubleQuotes)), pos: e.pos};
			case EConst(CInt(text, suffix)):
				final value = Std.parseInt(text);
				{expr: EConst(CInt(value == null ? text : Std.string(value), suffix)), pos: e.pos};
			case EConst(CFloat(text, suffix)):
				final value = Std.parseFloat(text);
				{expr: EConst(CFloat(Math.isNaN(value) ? text : Std.string(value), suffix)), pos: e.pos};
			case ESwitch(subject, cases, fallback):
				final all:Array<Case> = [
					for (c in cases)
						{values: [caseValue(c.values)], guard: expr(c.guard), expr: caseBody(c.expr)}
				];
				if (fallback != null)
					all.push({values: [{expr: EConst(CIdent("_")), pos: fallback.pos}], guard: null, expr: caseBody(fallback)});
				{expr: ESwitch(expr(subject), all, null), pos: e.pos};
			case _:
				haxe.macro.ExprTools.map(e, expr);
		}
	}

	/** One pattern for a case list; `case A, B:` becomes `A | B`, and `var t` becomes `t`. */
	static function caseValue(values:Array<Expr>):Expr {
		var combined:Null<Expr> = null;
		for (value in values) {
			final pattern = capture(expr(value));
			combined = combined == null ? pattern : {expr: EBinop(OpOr, combined, pattern), pos: pattern.pos};
		}
		return combined;
	}

	static function capture(pattern:Expr):Expr {
		return switch pattern.expr {
			case EVars([v]) if (v.expr == null && v.type == null): {expr: EConst(CIdent(v.name)), pos: pattern.pos};
			case _: pattern;
		}
	}

	static function caseBody(body:Null<Expr>):Null<Expr> {
		final normalized = expr(body);
		return normalized == null ? null : switch normalized.expr {
			case EBlock([]): null;
			case _: normalized;
		}
	}
}
