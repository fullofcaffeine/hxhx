/**
	Transient result of shared abstract binary-operator selection.

	The selected declaration is exact. `reverseArguments` records only call
	argument order; source operands still evaluate left-to-right. A compound source
	operator sets `requiresWriteback` only when Haxe falls back from `a op= b` to an
	ordinary `a = a op b` declaration because no explicit compound helper applied.
**/
class TyBoundAbstractBinaryOperator {
	final sourceOperator:String;
	final operatorInfo:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final requiresWriteback:Bool;

	public function new(sourceOperator:String, operatorInfo:TyAbstractBinaryOperatorInfo, reverseArguments:Bool, requiresWriteback:Bool) {
		this.sourceOperator = sourceOperator;
		this.operatorInfo = operatorInfo;
		this.reverseArguments = reverseArguments;
		this.requiresWriteback = requiresWriteback;
	}

	public function getSourceOperator():String
		return sourceOperator;

	public function getOperatorInfo():TyAbstractBinaryOperatorInfo
		return operatorInfo;

	public function getReverseArguments():Bool
		return reverseArguments;

	public function getRequiresWriteback():Bool
		return requiresWriteback;

	public function getSourceLeftParameterType():TyType
		return reverseArguments ? operatorInfo.getRightType() : operatorInfo.getLeftType();

	public function getSourceRightParameterType():TyType
		return reverseArguments ? operatorInfo.getLeftType() : operatorInfo.getRightType();
}
