import Ast;

/**
	A `let name = expr;` top-level declaration inside a `Module`.

	Why:
	- This is intentionally a class (not a typedef anonymous structure) so the
	  current portable lowering (record-backed classes) can represent it without
	  structural typing support.
**/
class LetDecl {
	final name:String;
	final expr:Expr;

	public function new(name:String, expr:Expr) {
		this.name = name;
		this.expr = expr;
	}

	public function getName():String {
		return name;
	}

	public function getExpr():Expr {
		return expr;
	}
}
