package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlTypeExpr;

enum OcamlTypeDeclKind {
	Alias(typ:OcamlTypeExpr);
	Record(fields:Array<OcamlTypeRecordField>);
	Variant(constructors:Array<OcamlVariantConstructor>);
}

