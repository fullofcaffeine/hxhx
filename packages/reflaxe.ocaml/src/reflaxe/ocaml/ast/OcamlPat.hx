package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlPatRecordField;
import reflaxe.ocaml.ast.OcamlTypeExpr;

enum OcamlPat {
	PAny;
	PVar(name:String);
	PConst(c:OcamlConst);
	PTuple(items:Array<OcamlPat>);
	POr(items:Array<OcamlPat>);
	PConstructor(name:String, args:Array<OcamlPat>);
	PRecord(fields:Array<OcamlPatRecordField>);

	/** Pattern type annotation: `(pat : typ)` */
	PAnnot(pat:OcamlPat, typ:OcamlTypeExpr);
}
