package reflaxe.ocaml.ast;

/** Compiler-only bindings can stay inside a module without becoming public exports. */
enum OcamlLetBindingVisibility {
	Exported;
	CompilerInternal;
}

typedef OcamlLetBinding = {
	final name:String;
	final expr:OcamlExpr;

	/** Present when declaration lowering supplied a complete function or checked static-cell type. */
	final ?signature:OcamlTypeExpr;

	/** Absence preserves ordinary exported binding behavior. */
	final ?visibility:OcamlLetBindingVisibility;
}
