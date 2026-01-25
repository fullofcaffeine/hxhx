class Eval {
	public static function eval(e:Expr):Int {
		return switch (e) {
			case EInt(v):
				v;
			case EBin(op, l, r):
				final a = eval(l);
				final b = eval(r);
				switch (op) {
					case Add: a + b;
					case Sub: a - b;
					case Mul: a * b;
					case Div:
						if (b == 0) throw "division by zero";
						Std.int(a / b);
				}
		}
	}
}
