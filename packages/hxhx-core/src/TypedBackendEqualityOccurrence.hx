/**
	Retain both checked operand types at one equality expression.
	Targets must select value or reference comparison from these types, even when
	the operands are calls or nested expressions rather than named local variables.
	The owning projection checks membership before exposing this record.
**/
class TypedBackendEqualityOccurrence {
	public final expression:HxExpr;
	public final left:HxExpr;
	public final right:HxExpr;
	public final leftType:TyType;
	public final rightType:TyType;
	public final equal:Bool;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (input.source.getTag() != Binary || input.source.getExpressions().length != 2)
			throw "equality occurrence requires a checked binary expression";
		final operation = input.source.getTexts()[0];
		if (operation != "==" && operation != "!=")
			throw "equality occurrence requires an equality operator";
		final operands = switch input.expression {
			case EBinop(op, a, b) if (op == operation): {left: a, right: b};
			case _: throw "equality projection changed its operator";
		};
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		left = operands.left;
		right = operands.right;
		leftType = input.source.getExpressions()[0].getType();
		rightType = input.source.getExpressions()[1].getType();
		equal = operation == "==";
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Equal text cannot substitute a different operand or executable owner. */
	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "equality occurrence belongs to another executable or changed after projection";
		switch expression {
			case EBinop(op, a, b) if (a == left && b == right && op == (equal ? "==" : "!=")):
			case _:
				throw "equality operands were replaced";
		}
	}
}
