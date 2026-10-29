/** Operations and expressions deliberately form a guarded, non-exhaustive pair. */
enum Operation {
	Read;
	Write;
	Compound(op:String);
}

/** A small recursive expression shape keeps the original nested enum pattern. */
enum Expression {
	Field(name:String);
	Binary(op:String, left:Expression, right:Expression);
	Literal(value:Int);
}

/** Construction either accepts the exact operation pair or throws its source value. */
class Access {
	public final kind:Operation;
	public final expression:Expression;

	public function new(kind:Operation, expression:Expression) {
		this.kind = kind;
		this.expression = expression;
		switch [this.kind, this.expression] {
			case [Read, Field(_)], [Write, Binary("=", _, _)]:
			case [Compound(expected), Binary(actual, _, _)] if (expected == actual):
			case _:
				throw "invalid operation pair";
		}
	}
}

/** Checks accepted arms and every distinct reason to enter the throwing fallback. */
class Main {
	static function attempt(label:String, operation:Operation, expression:Expression):Void {
		try {
			new Access(operation, expression);
			Sys.println(label + "=accepted");
		} catch (message:String) {
			Sys.println(label + "=" + message);
		}
	}

	static function main():Void {
		attempt("read", Read, Field("value"));
		attempt("write", Write, Binary("=", Field("value"), Literal(2)));
		attempt("compound", Compound("+="), Binary("+=", Field("value"), Literal(3)));
		attempt("read mismatch", Read, Literal(1));
		attempt("write mismatch", Write, Binary("+=", Field("value"), Literal(2)));
		attempt("guard mismatch", Compound("+="), Binary("-=", Field("value"), Literal(3)));
		attempt("shape mismatch", Compound("+="), Field("value"));
	}
}
