/**
	Recognizes compiler-owned type-operation markers in source-shaped projections.

	A NUL cannot occur in a parsed Haxe identifier. The marker therefore cannot be
	confused with an authored call. It carries only the evaluated child; the exact
	type target belongs to the executable projection's occurrence catalog.
**/
class TypedRuntimeTypeSource {
	public static inline final VALUE = "\x00hxhx.runtime.type.value";
	public static inline final TEST = "\x00hxhx.runtime.type.test";

	public static function isMarker(expression:HxExpr):Bool {
		return switch (expression) {
			case ECall(EIdent(VALUE), _) | ECall(EIdent(TEST), _): true;
			case _: false;
		};
	}

	/** Collect marker objects without interpreting names, targets, or opaque source text. */
	public static function inExpression(expression:Null<HxExpr>):Array<HxExpr> {
		final out = new Array<HxExpr>();
		TypedBackendSourceWalk.expression(expression, node -> {
			if (isMarker(node))
				out.push(node);
		});
		return out;
	}

	public static function inStatements(statements:Array<HxStmt>):Array<HxExpr> {
		final out = new Array<HxExpr>();
		for (statement in statements)
			TypedBackendSourceWalk.statement(statement, node -> {
				if (isMarker(node))
					out.push(node);
			}, _ -> {});
		return out;
	}
}
