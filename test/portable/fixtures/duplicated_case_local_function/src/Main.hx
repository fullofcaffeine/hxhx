/**
	A guarded `switch` case makes Haxe emit the next case body twice: once on the
	path where the guard fails, and once on the path where its pattern does not
	match. Each copy gets its own `wrap` local, but both copies of `wrap(...)`
	share one source span. The OCaml call planner must keep one call plan per
	copy instead of rejecting the two copies as conflicting plans for one call.
**/
enum Expr {
	EThis;
	EInt(value:Int);
	EBinop(op:String, left:Expr, right:Expr);
}

class Main {
	static function render(e:Expr, allowThis:Bool):String {
		return switch e {
			case EBinop(op, EThis, value) if (allowThis):
				"this" + op + render(value, allowThis);
			case EBinop(op, left, right):
				function wrap(text:String):String {
					return "(" + text + ")";
				}
				wrap(render(left, allowThis) + op + render(right, allowThis));
			case EThis:
				"this";
			case EInt(value):
				Std.string(value);
		}
	}

	static function main() {
		Sys.println(render(EBinop("+", EThis, EInt(1)), true));
		Sys.println(render(EBinop("=", EThis, EInt(1)), false));
		Sys.println(render(EBinop("-", EInt(2), EInt(1)), true));
		Sys.println(render(EBinop("*", EBinop("-", EThis, EInt(3)), EInt(4)), false));
	}
}
