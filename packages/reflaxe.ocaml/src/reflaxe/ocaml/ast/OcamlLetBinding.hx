package reflaxe.ocaml.ast;

typedef OcamlLetBinding = {
	final name:String;
	final expr:OcamlExpr;

	/** Present only when function lowering supplied a complete represented signature. */
	final ?signature:OcamlTypeExpr;
}
