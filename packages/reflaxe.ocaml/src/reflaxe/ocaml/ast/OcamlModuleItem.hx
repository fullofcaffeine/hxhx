package reflaxe.ocaml.ast;

enum OcamlModuleItem {
	ILet(bindings:Array<OcamlLetBinding>, isRec:Bool);
	IType(decls:Array<OcamlTypeDecl>, isRec:Bool);
}
