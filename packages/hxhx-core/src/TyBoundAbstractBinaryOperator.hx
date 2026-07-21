/**
	Transient result of shared abstract binary-operator selection.

	This record answers three questions once for every backend: which declared
	helper is called, how each source operand reaches the helper's parameter type,
	and whether a compound expression must store the result back. For example,
	`value += value` can call a helper that accepts `NullFloat, Float`, then convert
	the returned `Float` back to `NullFloat` before the assignment.

	`reverseArguments` changes only helper-call order; source operands still
	evaluate left-to-right. `requiresWriteback` is set only when Haxe falls back from
	`a op= b` to an ordinary `a = a op b` declaration because no explicit compound
	helper applied.
**/
class TyBoundAbstractBinaryOperator {
	final sourceOperator:String;
	final operatorInfo:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final requiresWriteback:Bool;
	final sourceLeftConversion:TyImplicitConversionPlan;
	final sourceRightConversion:TyImplicitConversionPlan;
	final resultConversion:Null<TyImplicitConversionPlan>;

	public function new(sourceOperator:String, operatorInfo:TyAbstractBinaryOperatorInfo, reverseArguments:Bool, requiresWriteback:Bool,
			sourceLeftConversion:TyImplicitConversionPlan, sourceRightConversion:TyImplicitConversionPlan, resultConversion:Null<TyImplicitConversionPlan>) {
		this.sourceOperator = sourceOperator;
		this.operatorInfo = operatorInfo;
		this.reverseArguments = reverseArguments;
		this.requiresWriteback = requiresWriteback;
		this.sourceLeftConversion = sourceLeftConversion;
		this.sourceRightConversion = sourceRightConversion;
		this.resultConversion = resultConversion;
	}

	public function getSourceOperator():String
		return sourceOperator;

	public function getOperatorInfo():TyAbstractBinaryOperatorInfo
		return operatorInfo;

	public function getReverseArguments():Bool
		return reverseArguments;

	public function getRequiresWriteback():Bool
		return requiresWriteback;

	public function getSourceLeftConversion():TyImplicitConversionPlan
		return sourceLeftConversion;

	public function getSourceRightConversion():TyImplicitConversionPlan
		return sourceRightConversion;

	public function getResultConversion():Null<TyImplicitConversionPlan>
		return resultConversion;

	public function getSourceLeftParameterType():TyType
		return reverseArguments ? operatorInfo.getRightType() : operatorInfo.getLeftType();

	public function getSourceRightParameterType():TyType
		return reverseArguments ? operatorInfo.getLeftType() : operatorInfo.getRightType();
}
