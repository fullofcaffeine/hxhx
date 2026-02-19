package reflaxe.ocaml.ast;

typedef OcamlMatchCase = {
	final pat:OcamlPat;
	final guard:Null<OcamlExpr>;
	final expr:OcamlExpr;
}
