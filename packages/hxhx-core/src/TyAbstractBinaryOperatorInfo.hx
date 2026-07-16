/**
	Canonical binary operator declaration owned by one abstract.

	This is declaration catalog data rather than a bound expression. Parameter
	types stay in declaration order, while `commutative` only authorizes the shared
	binder to reverse argument matching. It never changes source evaluation order.
**/
class TyAbstractBinaryOperatorInfo {
	final op:String;
	final declaration:TyDeclarationInfo;
	final leftType:TyType;
	final rightType:TyType;
	final resultType:TyType;
	final commutative:Bool;

	public function new(op:String, declaration:TyDeclarationInfo, leftType:TyType, rightType:TyType, resultType:TyType, commutative:Bool) {
		this.op = op;
		this.declaration = declaration;
		this.leftType = leftType;
		this.rightType = rightType;
		this.resultType = resultType;
		this.commutative = commutative;
	}

	public function getOperator():String
		return op;

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getLeftType():TyType
		return leftType;

	public function getRightType():TyType
		return rightType;

	public function getResultType():TyType
		return resultType;

	public function getIsCommutative():Bool
		return commutative;
}
