package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlMatchCase;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlRecordField;

enum OcamlBinop {
	Add;
	Concat; // ^
	Sub;
	Mul;
	Div;
	Mod;
	Cons; // ::

	Eq;
	Neq;
	PhysEq;  // ==
	PhysNeq; // !=
	Lt;
	Lte;
	Gt;
	Gte;

	And;
	Or;
}

enum OcamlUnop {
	Not;
	Neg;
	Deref; // !x
}

enum OcamlExpr {
	EConst(c:OcamlConst);
	EIdent(name:String);
	/** Raw OCaml snippet injected verbatim (escape hatch). */
	ERaw(code:String);

	/** `raise (<exn>)` */
	ERaise(exn:OcamlExpr);

	/**
	 * `let <rec?> <name> = <value> in <body>`
	 *
	 * Note: multi-binding lets can be represented by nesting.
	 */
	ELet(name:String, value:OcamlExpr, body:OcamlExpr, isRec:Bool);

	/** `fun p1 p2 -> body` */
	EFun(params:Array<OcamlPat>, body:OcamlExpr);

	/** Function application: `f a b` */
	EApp(fn:OcamlExpr, args:Array<OcamlExpr>);

	/** Infix operator expression. */
	EBinop(op:OcamlBinop, left:OcamlExpr, right:OcamlExpr);

	/** Unary operator expression. */
	EUnop(op:OcamlUnop, expr:OcamlExpr);

	EIf(cond:OcamlExpr, thenExpr:OcamlExpr, elseExpr:OcamlExpr);
	EMatch(scrutinee:OcamlExpr, cases:Array<OcamlMatchCase>);
	/** `try <body> with | <pat> -> <expr> ...` */
	ETry(body:OcamlExpr, cases:Array<OcamlMatchCase>);

	/** Sequencing: `e1; e2; ...` */
	ESeq(exprs:Array<OcamlExpr>);

	/** While loop: `while cond do body done` */
	EWhile(cond:OcamlExpr, body:OcamlExpr);

	/** List literal: `[a; b; c]` (used as a placeholder for arrays in early milestones). */
	EList(items:Array<OcamlExpr>);

	/** Record literal: `{ x = 1; y = 2 }` */
	ERecord(fields:Array<OcamlRecordField>);

	/** Field access: `e.x` */
	EField(expr:OcamlExpr, field:String);

	/** Assignment expression: `lhs := rhs` or `lhs <- rhs` */
	EAssign(op:OcamlAssignOp, lhs:OcamlExpr, rhs:OcamlExpr);

	ETuple(items:Array<OcamlExpr>);
}
