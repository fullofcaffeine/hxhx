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

	Each source operand is a closed `TyAbstractBinaryArgument`: an executable
	conversion for every ordinary selection, or, inside one indexed update only, an
	admission of the raw nullable getter value to its exact applied abstract
	parameter. Ordinary lowering must call `requireConversion()` and therefore
	rejects the admission. The result conversion is a separate executable fact.
**/
class TyBoundAbstractBinaryOperator {
	final sourceOperator:String;
	final operatorInfo:TyAbstractBinaryOperatorInfo;
	final reverseArguments:Bool;
	final requiresWriteback:Bool;
	final sourceLeftArgument:TyAbstractBinaryArgument;
	final sourceRightArgument:TyAbstractBinaryArgument;
	final resultConversion:Null<TyAbstractBinaryConversion>;

	public function new(sourceOperator:String, operatorInfo:TyAbstractBinaryOperatorInfo, reverseArguments:Bool, requiresWriteback:Bool,
			sourceLeftArgument:TyAbstractBinaryArgument, sourceRightArgument:TyAbstractBinaryArgument, resultConversion:Null<TyAbstractBinaryConversion>) {
		this.sourceOperator = sourceOperator;
		this.operatorInfo = operatorInfo;
		this.reverseArguments = reverseArguments;
		this.requiresWriteback = requiresWriteback;
		this.sourceLeftArgument = sourceLeftArgument;
		this.sourceRightArgument = sourceRightArgument;
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

	public function getSourceLeftArgument():TyAbstractBinaryArgument
		return sourceLeftArgument;

	public function getSourceRightArgument():TyAbstractBinaryArgument
		return sourceRightArgument;

	public function getResultConversion():Null<TyAbstractBinaryConversion>
		return resultConversion;

	public function getSourceLeftParameterType():TyType
		return reverseArguments ? operatorInfo.getRightType() : operatorInfo.getLeftType();

	public function getSourceRightParameterType():TyType
		return reverseArguments ? operatorInfo.getLeftType() : operatorInfo.getRightType();
}
