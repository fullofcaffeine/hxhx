/**
	The guarded case makes Haxe emit the next case body twice, each copy with
	its own `check` local. Storing `check(...)` into a `Null<Bool>` local asks
	the call plan whether the call produces the nullable Bool carrier while the
	OCaml syntax is built. That lookup must select the plan of its own copy.
**/
enum Expr {
	EThis;
	EInt(value:Int);
	EBinop(op:String, left:Expr, right:Expr);
}

class Main {
	static function render(e:Expr, allowThis:Bool):String {
		return switch e {
			case EBinop(op, EThis, value) if (allowThis): "this" + op + render(value, allowThis);
			case EBinop(op, left, right):
				function check(v:Int):Null<Bool> {
					return v > 0 ? true : null;
				}
				var flag:Null<Bool> = null;
				flag = check(op.length);
				var s:String = render(left, allowThis) + op + render(right, allowThis);
				(flag == true ? "(" : "[") + s + (flag == true ? ")" : "]");
			case EThis: "this";
			case EInt(value): Std.string(value);
		}
	}

	static function main() {
		Sys.println(render(EBinop("+", EThis, EInt(1)), true));
		Sys.println(render(EBinop("=", EThis, EInt(1)), false));
		Sys.println(render(EBinop("-", EInt(2), EInt(1)), true));
	}
}
