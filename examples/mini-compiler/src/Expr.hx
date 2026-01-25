enum Expr {
	EInt(v:Int);
	EBin(op:BinOp, left:Expr, right:Expr);
}

