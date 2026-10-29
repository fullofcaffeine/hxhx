/**
	Keep checked bitwise operands attached to their exact executable expression.
	Native targets must distinguish Int operations from Dynamic dispatch and abstract
	operators without guessing from source spelling or generated target code.
 */
class TypedBackendBitwiseOccurrence {
	public final expression:HxExpr;
	public final left:HxExpr;
	public final right:HxExpr;
	public final operation:String;
	public final leftType:TyType;
	public final rightType:TyType;
	public final resultType:TyType;

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
			throw "bitwise occurrence requires two checked operands";
		operation = input.source.getTexts()[0];
		if (!supports(operation))
			throw "bitwise occurrence requires a bitwise operator";
		final operands = switch input.expression {
			case EBinop(op, a, b) if (op == operation): {left: a, right: b};
			case _: throw "bitwise projection changed its operator";
		};
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		left = operands.left;
		right = operands.right;
		leftType = input.source.getExpressions()[0].getType();
		rightType = input.source.getExpressions()[1].getType();
		resultType = input.source.getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public static function supports(operation:String):Bool {
		return switch operation {
			case "&" | "|" | "^" | "<<" | ">>" | ">>>": true;
			case _: false;
		};
	}

	/** Only concrete Int inputs use the native Int representation on both sides. */
	public function isConcreteInt():Bool {
		return leftType.getSemanticKey() == "primitive:Int"
			&& rightType.getSemanticKey() == "primitive:Int"
			&& resultType.getSemanticKey() == "primitive:Int";
	}

	/** Equal text cannot replace the original operands or move facts to another body. */
	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "bitwise occurrence belongs to another executable or changed after projection";
		switch expression {
			case EBinop(op, a, b) if (op == operation && a == left && b == right):
			case _:
				throw "bitwise operands were replaced";
		}
	}
}
