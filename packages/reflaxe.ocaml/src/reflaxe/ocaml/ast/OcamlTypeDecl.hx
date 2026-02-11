package reflaxe.ocaml.ast;

typedef OcamlTypeDecl = {
	final name:String;
	final params:Array<String>; // without leading `'`
	final kind:OcamlTypeDeclKind;
}

