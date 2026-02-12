import Ast;
import Module;

/**
	A tiny “type checker” used to exercise compiler-like structure.

	For now everything is an `Int`, but we still build a symbol table and validate
	that all `EVar` references are defined.
**/
class TypeChecker {
	public static function checkModule(m:Module):Void {
		final env = new haxe.ds.StringMap<Bool>();
		var i = 0;
		final decls = m.getDecls();
		while (i < decls.length) {
			final d = decls[i];
			checkExpr(d.getExpr(), env);
			env.set(d.getName(), true);
			i++;
		}
	}

	static function checkExpr(e:Expr, env:haxe.ds.StringMap<Bool>):Void {
		switch (e) {
			case EInt(_):
			case EVar(name):
				if (!env.exists(name)) throw "Unknown variable: " + name;
			case EBin(_, a, b):
				checkExpr(a, env);
				checkExpr(b, env);
		}
	}
}
