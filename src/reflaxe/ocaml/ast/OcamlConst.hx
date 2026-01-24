package reflaxe.ocaml.ast;

enum OcamlConst {
	CInt(value:Int);
	CFloat(value:String);
	CString(value:String);
	CBool(value:Bool);
	CUnit;
}
