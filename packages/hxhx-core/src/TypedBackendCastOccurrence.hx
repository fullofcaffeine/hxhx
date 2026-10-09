/**
	Retain exact source and destination types for a projected cast occurrence.
	A target must still choose the runtime operation; equal hint text cannot prove
	that a cast preserves representation. Compiler callable ascriptions are separate.
 */
class TypedBackendCastOccurrence {
	final ownerIdentity:String;
	final bodyRevision:String;
	final expression:HxExpr;
	final operand:HxExpr;
	final sourceType:TyType;
	final targetType:TyType;
	final preservesRepresentation:Bool;
	final fingerprint:String;

	public function new(input:{
		ownerIdentity:String,
		bodyRevision:String,
		source:TypedExpr,
		operand:HxExpr
	}) {
		if (input.ownerIdentity == null
			|| input.bodyRevision == null
			|| input.source == null
			|| input.operand == null
			|| input.source.getTag() != Cast
			|| input.source.getExpressions().length != 1)
			throw "cast occurrence requires its exact typed owner and operand";
		ownerIdentity = input.ownerIdentity;
		bodyRevision = input.bodyRevision;
		operand = input.operand;
		sourceType = input.source.getExpressions()[0].getType();
		targetType = input.source.getType();
		preservesRepresentation = input.source.isRepresentationPreservingCast();
		expression = ECast(operand, input.source.getTexts()[0]);
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function getExpression():HxExpr
		return expression;

	public function getOwnerIdentity():String
		return ownerIdentity;

	/** Only a hint-free cast has the authored unchecked contract; hinted forms need their own operation. */
	public function isUnchecked():Bool
		return switch expression {
			case ECast(_, hint): hint.length == 0 && !preservesRepresentation;
			case _: false;
		};

	public function getOperand():HxExpr
		return operand;

	public function getSourceType():TyType
		return sourceType;

	public function getTargetType():TyType
		return targetType;

	public function isRepresentationPreserving():Bool
		return preservesRepresentation;

	/** A cast cannot borrow another executable's types or replace its original operand. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != ownerIdentity || revision != bodyRevision)
			throw "cast occurrence belongs to another executable or revision";
		switch expression {
			case ECast(child, _) if (child == operand):
			case _:
				throw "cast occurrence operand was replaced";
		}
		if (fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "cast occurrence was mutated";
	}
}
