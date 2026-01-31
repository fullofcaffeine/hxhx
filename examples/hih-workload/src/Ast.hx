enum BinOp {
	Add;
	Sub;
	Mul;
	Div;
}

enum Expr {
	EInt(v:Int);
	EVar(name:String);
	EBin(op:BinOp, left:Expr, right:Expr);
}
