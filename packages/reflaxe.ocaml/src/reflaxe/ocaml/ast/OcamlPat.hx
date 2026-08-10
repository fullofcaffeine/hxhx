package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlPatRecordField;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;

enum OcamlPat {
	PAny;
	PVar(name:String);
	PConst(c:OcamlConst);
	PTuple(items:Array<OcamlPat>);
	POr(items:Array<OcamlPat>);
	PConstructor(name:String, args:Array<OcamlPat>);

	/**
		A private runtime constructor approved by one sealed lowering decision.

		The reference keeps the hidden decision identity until final output checking.
		The printer uses only its exact symbol, so this node prints like an ordinary
		OCaml constructor and cannot choose different catch behavior.
	**/
	PRuntimeConstructor(reference:OcamlRuntimeReference, args:Array<OcamlPat>);

	PRecord(fields:Array<OcamlPatRecordField>);

	/** Pattern type annotation: `(pat : typ)` */
	PAnnot(pat:OcamlPat, typ:OcamlTypeExpr);
}
