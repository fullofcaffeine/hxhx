/**
	Canonical unary operator declaration owned by an abstract.

	This is declaration-catalog data, not a bound expression. Expression typing
	will later choose one candidate and lower its exact call/body before any
	backend sees the operation. An unannotated inline declaration can retain an
	Unknown result here; mandatory shared program sealing replaces that placeholder
	with the helper body's inferred semantic return type before backend emission.
**/
class TyAbstractOperatorInfo {
	final unaryOperator:HxUnaryOperator;
	final fixity:HxUnaryFixity;
	final declaration:TyDeclarationInfo;
	final operandType:TyType;
	final resultType:TyType;

	public function new(unaryOperator:HxUnaryOperator, fixity:HxUnaryFixity, declaration:TyDeclarationInfo, operandType:TyType, resultType:TyType) {
		this.unaryOperator = unaryOperator;
		this.fixity = fixity;
		this.declaration = declaration;
		this.operandType = operandType;
		this.resultType = resultType;
	}

	public function getOperator():HxUnaryOperator
		return unaryOperator;

	public function getFixity():HxUnaryFixity
		return fixity;

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getOperandType():TyType
		return operandType;

	public function getResultType():TyType
		return resultType;
}
