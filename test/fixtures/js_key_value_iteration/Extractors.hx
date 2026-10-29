/** Runtime observations for the enum and object patterns formerly checked as raw emitter text. */
class Extractors {
	public static function run():Void {
		final full = stack(FilePos(Method("Owner", "run"), "Main.hx", 17, 8));
		if (full.file != "Main.hx" || full.line != 17 || full.method != "run")
			throw "nested stack extractor bindings";
		final partial = stack(FilePos(Other, "Other.hx", 23, 0));
		if (partial.file != "Other.hx" || partial.line != 23 || partial.method != null)
			throw "nested stack extractor fallback";
		final empty = stack(Method("Ignored", "ignored"));
		if (empty.file != null || empty.line != null || empty.method != null)
			throw "outer stack extractor fallback";
		if (object(EParenthesis({expr: EConst(CString("parenthesis"))})) != "parenthesis"
			|| object(EUntyped({expr: EConst(CString("untyped"))})) != "untyped")
			throw "object extractor alternatives";
		if (object(EArray({expr: EOther}, {expr: EConst(CInt("42"))})) != "42"
			|| object(EArray({expr: EOther}, {expr: EConst(CFloat("1.25"))})) != "1.25")
			throw "nested numeric extractor alternatives";
		if (object(EOther) != "none"
			|| object(EUntyped({expr: EOther})) != "none"
			|| object(EArray({expr: EOther}, {expr: EConst(CString("wrong"))})) != "none")
			throw "object extractor fallback";
	}

	/** Optional fields express the empty result and preserve each successful assignment. */
	static function stack(item:StackItem):StackResult {
		var result:StackResult = {};
		switch item {
			case FilePos(s, f, l, _):
				result.file = f;
				result.line = l;
				switch s {
					case Method(_, m): result.method = m;
					case _:
				}
			case _:
		}
		return result;
	}

	/** Keep the original OR patterns, nested field paths, and real Std.string conversion. */
	static function object(payload:ExprDef):String {
		var out = null;
		switch payload {
			case EParenthesis({expr: EConst(CString(s))}) | EUntyped({expr: EConst(CString(s))}):
				out = s;
			case EArray(_, {expr: EConst(CInt(i) | CFloat(i))}):
				out = Std.string(i);
			case _:
				out = "none";
		}
		return out;
	}
}

/** A stack observation contains only the fields supplied by the matched constructors. */
typedef StackResult = {
	var ?file:String;
	var ?line:Int;
	var ?method:String;
}

/** Small independent inputs preserve the original extractor's constructor positions. */
enum StackItem {
	FilePos(item:StackItem, file:String, line:Int, column:Int);
	Method(owner:String, method:String);
	Other;
}

typedef Expr = {var expr:ExprDef;}

/** Authored object fields nest inside enum payloads, including both OR alternatives. */
enum ExprDef {
	EParenthesis(value:Expr);
	EUntyped(value:Expr);
	EConst(value:Constant);
	EArray(left:Expr, right:Expr);
	EOther;
}

/** Numeric tokens remain strings, as in the original macro-expression-shaped pattern. */
enum Constant {
	CString(value:String);
	CInt(value:String);
	CFloat(value:String);
}
