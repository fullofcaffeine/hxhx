import Ast;
import Module;

class Eval {
	public static function evalModule(m:Module):Int {
		final env = new haxe.ds.StringMap<Int>();
		var last = 0;
		final decls = m.getDecls();
		var i = 0;
		while (i < decls.length) {
			final d = decls[i];
			final v = evalExpr(d.getExpr(), env);
			env.set(d.getName(), v);
			last = v;
			i++;
		}
		return last;
	}

	static function evalExpr(e:Expr, env:haxe.ds.StringMap<Int>):Int {
		return switch (e) {
			case EInt(v): v;
			case EVar(name): env.get(name);
			case EBin(op, a, b):
				final x = evalExpr(a, env);
				final y = evalExpr(b, env);
				switch (op) {
					case Add: x + y;
					case Sub: x - y;
					case Mul: x * y;
					case Div: Std.int(x / y);
				}
		}
	}
}
