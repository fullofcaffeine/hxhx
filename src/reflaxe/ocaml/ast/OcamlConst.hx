package reflaxe.ocaml.ast;

enum OcamlConst {
	CInt(value:String);
	CFloat(value:String);
	CString(value:String);
	CBool(value:Bool);
	CUnit;
}

