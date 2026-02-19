package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlTypeRecordField;

enum OcamlTypeExpr {
	/** A type identifier: `int`, `string`, `t`, `My_mod.t` */
	TIdent(name:String);

	/** Type application: `'a list`, `(int, string) result` */
	TApp(name:String, params:Array<OcamlTypeExpr>);

	/** Function type: `a -> b` */
	TArrow(from:OcamlTypeExpr, to:OcamlTypeExpr);

	/** Tuple type: `a * b * c` */
	TTuple(items:Array<OcamlTypeExpr>);

	/** Type variable: `'a` */
	TVar(name:String);

	/** Record type: `{ mutable x : int; y : string }` */
	TRecord(fields:Array<OcamlTypeRecordField>);
}
