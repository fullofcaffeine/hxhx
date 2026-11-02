/**
	Retain both checked operand types at one String concatenation (`a + b`
	whose result is String).

	Why: a target turns each operand into text, and the right conversion
	depends on the operand's type, not on how it is spelled. A Bool static
	field, a `Null<Bool>` local, a Map read, or an `is` test all look like an
	ordinary value in syntax. Without its type, native OCaml prints such a Bool
	as `1` or `0`, because an OCaml `bool` and `int` share one runtime shape.

	The owning projection checks membership before exposing this record.
**/
class TypedBackendStringConcatOccurrence {
	public final expression:HxExpr;
	public final left:HxExpr;
	public final right:HxExpr;
	public final leftType:TyType;
	public final rightType:TyType;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	/** Whether this checked binary expression is a String concatenation. */
	public static function supports(source:TypedExpr):Bool {
		return source.getTag() == Binary
			&& source.getTexts()[0] == "+"
			&& source.getExpressions().length == 2
			&& source.getType() != null
			&& source.getType().getSemanticKey() == "primitive:String";
	}

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (!supports(input.source))
			throw "string concatenation occurrence requires a checked String addition";
		final operands = switch input.expression {
			case EBinop("+", a, b): {left: a, right: b};
			case _: throw "string concatenation projection changed its operator";
		};
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		left = operands.left;
		right = operands.right;
		leftType = input.source.getExpressions()[0].getType();
		rightType = input.source.getExpressions()[1].getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** The checked type of `operand` when it is one side of this concatenation, or null. */
	public function operandType(operand:HxExpr):Null<TyType>
		return operand == left ? leftType : operand == right ? rightType : null;

	/** Equal text cannot substitute a different operand or executable owner. */
	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "string concatenation occurrence belongs to another executable or changed after projection";
		switch expression {
			case EBinop("+", a, b) if (a == left && b == right):
			case _:
				throw "string concatenation operands were replaced";
		}
	}
}
